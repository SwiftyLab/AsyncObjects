import XCTest
@testable import AsyncObjects

@MainActor
class AsyncEventTests: XCTestCase {

    func testWait() async throws {
        let event = AsyncEvent(signaledInitially: false)
        try await Self.checkWait(for: event)
    }

    func testLockAndWait() async throws {
        let event = AsyncEvent()
        event.reset()
        try await Self.sleep(seconds: 0.001)
        try await Self.checkWait(for: event)
    }

    func testReleasedWait() async throws {
        let event = AsyncEvent()
        try await Self.checkWait(for: event, durationInSeconds: 0)
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

@MainActor
class AsyncEventTimeoutTests: XCTestCase {

    func testWait() async throws {
        let event = AsyncEvent(signaledInitially: false)
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
        }
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await event.wait(forSeconds: 2)
        }
    }

    func testReleasedWait() async throws {
        let event = AsyncEvent()
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await event.wait(forSeconds: 2)
        }
    }

    func testWaitTimeout() async throws {
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
}

#if swift(>=5.7)
@MainActor
class AsyncEventClockTimeoutTests: XCTestCase {

    func testWait() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        Task.detached {
            try await Self.sleep(seconds: 1, clock: clock)
            event.signal()
        }
        try await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            try await event.wait(forSeconds: 2, clock: clock)
        }
    }

    func testReleasedWait() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent()
        try await Self.checkExecInterval(duration: .seconds(0), clock: clock) {
            try await event.wait(forSeconds: 2, clock: clock)
        }
    }

    func testWaitTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            do {
                try await event.wait(forSeconds: 1, clock: clock)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }
}
#endif

@MainActor
class AsyncEventCancellationTests: XCTestCase {

    func testWaitCancellation() async throws {
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

    func testAlreadyCancelledTask() async throws {
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
}

fileprivate extension XCTestCase {

    static func checkWait(
        for event: AsyncEvent,
        signalIn interval: UInt64 = 1,
        durationInSeconds seconds: Int = 1
    ) async throws {
        Task.detached {
            try await Self.sleep(seconds: interval)
            event.signal()
        }
        try await Self.checkExecInterval(
            durationInSeconds: seconds
        ) { try await event.wait() }
    }
}
