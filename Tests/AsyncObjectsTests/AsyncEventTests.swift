import XCTest
@testable import AsyncObjects

@MainActor
class AsyncEventTests: XCTestCase {

    func testSignal() async throws {
        let event = AsyncEvent(signaledInitially: false)
        event.signal()
        try await event.wait(forSeconds: 3)
    }

    func testSignalAfterSomeWait() async throws {
        let event = AsyncEvent(signaledInitially: false)
        Task {
            try await Task.sleep(seconds: 1)
            event.signal()
        }
        try await event.wait(forSeconds: 10)
    }

    func testResetSignal() async throws {
        let event = AsyncEvent()
        event.reset()
        try await waitUntil(event, timeout: 3) { !$0.signalled }
        event.signal()
        try await event.wait(forSeconds: 3)
    }

    func testSignalled() async throws {
        let event = AsyncEvent()
        try await event.wait(forSeconds: 3)
    }

    func testDeinit() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let task = Task.detached { event.signal() }
        try await event.wait(forSeconds: 3)
        await task.value
        self.addTeardownBlock { [weak event] in
            try await waitUntil(event, timeout: 10) { $0.assertReleased() }
        }
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let event = AsyncEvent(signaledInitially: false)
                    try await withThrowingTaskGroup(of: Void.self) { g in
                        g.addTask { try await event.wait(forSeconds: 3) }
                        g.addTask { event.signal() }
                        try await g.waitForAll()
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

@MainActor
class AsyncEventTimeoutTests: XCTestCase {

    func testSignal() async throws {
        let event = AsyncEvent(signaledInitially: false)
        do {
            try await event.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testResetSignal() async throws {
        let event = AsyncEvent()
        event.reset()
        try await waitUntil(event, timeout: 3) { !$0.signalled }
        do {
            try await event.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }
}

#if swift(>=5.7)
@MainActor
class AsyncEventClockTimeoutTests: XCTestCase {

    func testSignal() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        do {
            try await event.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
    }

    func testResetSignal() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent()
        event.reset()
        try await waitUntil(event, timeout: 3) { !$0.signalled }
        do {
            try await event.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
    }
}
#endif

@MainActor
class AsyncEventCancellationTests: XCTestCase {

    func testCancellation() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let task = Task.detached { try await event.wait() }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {}
    }

    func testAlreadyCancelledTask() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let task = Task.detached {
            do {
                try await event.wait()
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            try await event.wait()
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {}
    }
}
