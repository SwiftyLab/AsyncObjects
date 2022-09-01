import XCTest
@testable import AsyncObjects

@MainActor
class AsyncCountdownEventTests: XCTestCase {

    func testCountdownWaitWithoutIncrement() async throws {
        let event = AsyncCountdownEvent()
        await Self.checkExecInterval(durationInSeconds: 0) {
            await event.wait()
        }
    }

    func testCountdownWaitZeroTimeoutWithoutIncrement() async throws {
        let event = AsyncCountdownEvent()
        await Self.checkExecInterval(durationInSeconds: 0) {
            let result = await event.wait(forSeconds: 0)
            XCTAssertEqual(result, .success)
        }
    }

    static func signalCountdownEvent(
        _ event: AsyncCountdownEvent,
        times count: UInt
    ) {
        Task.detached {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<count {
                    group.addTask {
                        let duration = UInt64(Double(i + 1) * 5E8)
                        try await Task.sleep(nanoseconds: duration)
                        await event.signal()
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCountdownWaitWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 5) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 3) {
            let result = await event.wait(forSeconds: 3)
            XCTAssertEqual(result, .timedOut)
        }
    }

    func testCountdownWaitWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        await event.increment(by: 10)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInRange: 3.5..<4) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        await event.increment(by: 10)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 2) {
            let result = await event.wait(forSeconds: 2)
            XCTAssertEqual(result, .timedOut)
        }
    }

    func testCountdownWaitWithLimitInitialCountAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3, initial: 2)
        await event.increment(by: 10)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInRange: 4.5..<5) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithLimitInitialCountAndIncrement()
        async throws
    {
        let event = AsyncCountdownEvent(until: 3, initial: 3)
        await event.increment(by: 10)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 3) {
            let result = await event.wait(forSeconds: 3)
            XCTAssertEqual(result, .timedOut)
        }
    }

    func testCountdownWaitWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Self.sleep(seconds: 3)
            await event.reset()
        }
        await Self.checkExecInterval(durationInSeconds: 3) {
            await event.wait()
        }
    }

    func testCountdownWaitWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Self.sleep(seconds: 3)
            await event.reset(to: 2)
            await Self.signalCountdownEvent(event, times: 10)
        }
        await Self.checkExecInterval(durationInSeconds: 4) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Self.sleep(seconds: 3)
            await event.reset()
        }
        await Self.checkExecInterval(durationInSeconds: 2) {
            await event.wait(forSeconds: 2)
        }
    }

    func testCountdownWaitTimeoutWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Self.sleep(seconds: 3)
            await event.reset(to: 6)
            await Self.signalCountdownEvent(event, times: 10)
        }
        await Self.checkExecInterval(durationInSeconds: 3) {
            await event.wait(forSeconds: 3)
        }
    }

    func testCountdownWaitWithConcurrentIncrementAndResetToCount() async throws
    {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Self.sleep(seconds: 2)
            await event.reset(to: 2)
        }
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInRange: 2.5...3.2) {
            await event.wait()
        }
    }

    func testDeinit() async throws {
        let event = AsyncCountdownEvent(until: 0, initial: 1)
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
        }
        await event.wait()
        self.addTeardownBlock { [weak event] in
            XCTAssertNil(event)
        }
    }

    func testWaitCancellationWhenTaskCancelled() async throws {
        let event = AsyncCountdownEvent(initial: 1)
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                await event.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testWaitCancellationForAlreadyCancelledTask() async throws {
        let event = AsyncCountdownEvent(initial: 1)
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                await event.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testConcurrentAccess() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let event = AsyncCountdownEvent(initial: 1)
                    await Self.checkExecInterval(durationInSeconds: 0) {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await event.wait() }
                            group.addTask { await event.signal() }
                            await group.waitForAll()
                        }
                    }
                }
                await group.waitForAll()
            }
        }
    }
}
