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
            event.signal()
        }
        try await Self.checkExecInterval(
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
        event.reset()
        try await Self.sleep(seconds: 0.001)
        try await checkWait(for: event)
    }

    func testReleasedEventWait() async throws {
        let event = AsyncEvent()
        try await checkWait(for: event, durationInSeconds: 0)
    }

    func testEventWaitWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        await Self.checkExecInterval(durationInSeconds: 1) {
            do {
                try await event.wait(forSeconds: 1)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testEventWaitWithZeroTimeout() async throws {
        let event = AsyncEvent(signaledInitially: true)
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await event.wait(forNanoseconds: 0)
        }
    }

    func testEventWaitSuccessWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
        }
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await event.wait(forSeconds: 2)
        }
    }

    func testReleasedEventWaitSuccessWithoutTimeout() async throws {
        let event = AsyncEvent()
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await event.wait(forSeconds: 2)
        }
    }

    func testDeinit() async throws {
        let event = AsyncEvent(signaledInitially: false)
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
        }
        try await event.wait()
        self.addTeardownBlock { [weak event] in
            try await Self.sleep(seconds: 1)
            XCTAssertNil(event)
        }
    }

    func testWaitCancellationWhenTaskCancelled() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await event.wait()
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
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
                try? await event.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let event = AsyncEvent(signaledInitially: false)
                    try await Self.checkExecInterval(durationInSeconds: 0) {
                        try await withThrowingTaskGroup(of: Void.self) { g in
                            g.addTask { try await event.wait() }
                            g.addTask { event.signal() }
                            try await g.waitForAll()
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}
