import XCTest
@testable import AsyncObjects

class AsyncCountdownEventTests: XCTestCase {

    func testCountdownWaitWithoutIncrement() async throws {
        let event = AsyncCountdownEvent()
        await checkExecInterval(durationInSeconds: 0) {
            await event.wait()
        }
    }

    func testCountdownWaitZeroTimeoutWithoutIncrement() async throws {
        let event = AsyncCountdownEvent()
        await checkExecInterval(durationInSeconds: 0) {
            let result = await event.wait(forNanoseconds: 0)
            XCTAssertEqual(result, .success)
        }
    }

    func signalCountdownEvent(_ event: AsyncCountdownEvent, times count: UInt) {
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
        signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInSeconds: 5) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInSeconds: 3) {
            let result = await event.wait(forNanoseconds: UInt64(3E9))
            XCTAssertEqual(result, .timedOut)
        }
    }

    func testCountdownWaitWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        await event.increment(by: 10)
        signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInSeconds: 3.5) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        await event.increment(by: 10)
        signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInSeconds: 2) {
            let result = await event.wait(forNanoseconds: UInt64(2E9))
            XCTAssertEqual(result, .timedOut)
        }
    }

    func testCountdownWaitWithLimitInitialCountAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3, initial: 2)
        await event.increment(by: 10)
        signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInRange: 4.5..<5) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithLimitInitialCountAndIncrement()
        async throws
    {
        let event = AsyncCountdownEvent(until: 3, initial: 3)
        await event.increment(by: 10)
        signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInSeconds: 3) {
            let result = await event.wait(forNanoseconds: UInt64(3E9))
            XCTAssertEqual(result, .timedOut)
        }
    }

    func testCountdownWaitWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(3E9))
            await event.reset()
        }
        await checkExecInterval(durationInSeconds: 3) {
            await event.wait()
        }
    }

    func testCountdownWaitWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(3E9))
            await event.reset(to: 2)
            self.signalCountdownEvent(event, times: 10)
        }
        await checkExecInterval(durationInSeconds: 4) {
            await event.wait()
        }
    }

    func testCountdownWaitTimeoutWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(3E9))
            await event.reset()
        }
        await checkExecInterval(durationInSeconds: 2) {
            await event.wait(forNanoseconds: UInt64(2E9))
        }
    }

    func testCountdownWaitTimeoutWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(3E9))
            await event.reset(to: 6)
            self.signalCountdownEvent(event, times: 10)
        }
        await checkExecInterval(durationInSeconds: 3) {
            await event.wait(forNanoseconds: UInt64(3E9))
        }
    }

    func testCountdownWaitWithConcurrentIncrementAndResetToCount() async throws
    {
        let event = AsyncCountdownEvent()
        await event.increment(by: 10)
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(2E9))
            await event.reset(to: 2)
        }
        self.signalCountdownEvent(event, times: 10)
        await checkExecInterval(durationInRange: 2.5...3.1) {
            await event.wait()
        }
    }
}
