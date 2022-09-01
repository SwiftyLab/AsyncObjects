import XCTest
@testable import AsyncObjects

@MainActor
class AsyncEventTests: XCTestCase {

    func checkWait(
        for event: AsyncEvent,
        signalIn interval: UInt64 = 1,
        durationInSeconds seconds: Int = 1
    ) async throws {
        Task.detached {
            try await Self.sleep(seconds: interval)
            await event.signal()
        }
        await Self.checkExecInterval(
            durationInSeconds: seconds,
            for: event.wait
        )
    }

    func testEventWait() async throws {
        let event = AsyncEvent(signaledInitially: false)
        try await checkWait(for: event)
    }

    func testEventLockAndWait() async throws {
        let event = AsyncEvent()
        await event.reset()
        try await checkWait(for: event)
    }

    func testReleasedEventWait() async throws {
        let event = AsyncEvent()
        try await checkWait(for: event, durationInSeconds: 0)
    }

    func testEventWaitWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        var result: TaskTimeoutResult = .success
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await event.wait(forSeconds: 1)
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testEventWaitWithZeroTimeout() async throws {
        let event = AsyncEvent(signaledInitially: true)
        var result: TaskTimeoutResult = .success
        await Self.checkExecInterval(durationInSeconds: 0) {
            result = await event.wait(forNanoseconds: 0)
        }
        XCTAssertEqual(result, .success)
    }

    func testEventWaitSuccessWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
        }
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await event.wait(forSeconds: 2)
        }
        XCTAssertEqual(result, .success)
    }

    func testReleasedEventWaitSuccessWithoutTimeout() async throws {
        let event = AsyncEvent()
        var result: TaskTimeoutResult = .timedOut
        await Self.checkExecInterval(durationInSeconds: 0) {
            result = await event.wait(forSeconds: 2)
        }
        XCTAssertEqual(result, .success)
    }

    func testDeinit() async throws {
        let event = AsyncEvent(signaledInitially: false)
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
        let event = AsyncEvent(signaledInitially: false)
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                await event.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testWaitCancellationForAlreadyCancelledTask() async throws {
        let event = AsyncEvent(signaledInitially: false)
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
                    let event = AsyncEvent(signaledInitially: false)
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
