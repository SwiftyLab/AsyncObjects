import XCTest
@testable import AsyncObjects

@MainActor
class AsyncCountdownEventTests: XCTestCase {

    func testWithoutIncrement() async throws {
        let event = AsyncCountdownEvent()
        try await event.wait(forSeconds: 3)
    }

    func testWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 10)
        try await event.wait(forSeconds: 5)
    }

    func testWithIncrementSignalAfterSomeWait() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        Task {
            try await Task.sleep(seconds: 1)
            event.signal(repeat: 10)
        }
        try await event.wait(forSeconds: 10)
    }

    func testWithOverIncrement() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 15)
        try await event.wait(forSeconds: 5)
    }

    func testWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 7)
        try await event.wait(forSeconds: 5)
    }

    func testWithLimitInitialCountAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3, initial: 2)
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 12)
        event.signal(repeat: 9)
        try await event.wait(forSeconds: 5)
    }

    func testWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        var count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.reset()
        let initial = await event.initialCount
        count = await event.currentCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(initial, 0)
        let isSet = await event.isSet
        XCTAssertTrue(isSet)
        try await event.wait(forSeconds: 5)
    }

    func testWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        var count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.reset(to: 2)
        let initial = await event.initialCount
        count = await event.currentCount
        XCTAssertEqual(count, 2)
        XCTAssertEqual(initial, 2)
        event.signal(repeat: 2)
        let isSet = await event.isSet
        XCTAssertTrue(isSet)
        try await event.wait(forSeconds: 5)
    }

    func testWithConcurrentIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        Task.detached {
            let count = await event.currentCount
            XCTAssertEqual(count, 6)
            event.reset(to: 2)
        }
        event.signal(repeat: 4)
        try await waitUntil(event, timeout: 10) { await $0.currentCount == 2 }
        event.signal(repeat: 2)
        try await event.wait(forSeconds: 5)
    }

    func testDeinit() async throws {
        let event = AsyncCountdownEvent(until: 0, initial: 1)
        event.signal()
        try await event.wait(forSeconds: 5)
        self.addTeardownBlock { [weak event] in
            try await waitUntil(event, timeout: 10) { $0.assertReleased() }
        }
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let event = AsyncCountdownEvent(initial: 1)
                    try await withThrowingTaskGroup(of: Void.self) { g in
                        g.addTask { try await event.wait(forSeconds: 5) }
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
class AsyncCountdownEventTimeoutTests: XCTestCase {

    func testTimeoutWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 9)
        do {
            try await event.wait(forSeconds: 5)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {
            let count = await event.currentCount
            XCTAssertEqual(count, 1)
        }
    }

    func testTimeoutWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 6)
        do {
            try await event.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {
            let count = await event.currentCount
            XCTAssertEqual(count, 4)
        }
    }

    func testTimeoutWithLimitInitialCountAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3, initial: 3)
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 13)
        event.signal(repeat: 9)
        do {
            try await event.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {
            let count = await event.currentCount
            XCTAssertEqual(count, 4)
        }
    }

    func testTimeoutWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        Task.detached { event.signal(repeat: 8) }
        Task.detached {
            try await waitUntil(event, timeout: 5) {
                await $0.currentCount <= 6
            }
            event.reset(to: 6)
        }
        do {
            try await event.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {
            let count = await event.currentCount
            XCTAssertGreaterThanOrEqual(count, 2)
            XCTAssertLessThanOrEqual(count, 6)
        }
    }
}

#if swift(>=5.7)
@MainActor
class AsyncCountdownEventClockTimeoutTests: XCTestCase {

    func testTimeoutWithIncrement() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 9)
        do {
            try await event.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {
            let count = await event.currentCount
            XCTAssertEqual(count, 1)
        }
    }

    func testTimeoutWithLimitAndIncrement() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent(until: 3)
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        event.signal(repeat: 6)
        do {
            try await event.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {
            let count = await event.currentCount
            XCTAssertEqual(count, 4)
        }
    }

    func testTimeoutWithLimitInitialCountAndIncrement() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent(until: 3, initial: 3)
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 13)
        event.signal(repeat: 9)
        do {
            try await event.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {
            let count = await event.currentCount
            XCTAssertEqual(count, 4)
        }
    }

    func testTimeoutWithIncrementAndResetToCount() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        let count = await event.currentCount
        XCTAssertEqual(count, 10)
        Task.detached { event.signal(repeat: 8) }
        Task.detached {
            try await waitUntil(event, timeout: 5) {
                await $0.currentCount <= 6
            }
            event.reset(to: 6)
        }
        do {
            try await event.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {
            let count = await event.currentCount
            XCTAssertGreaterThanOrEqual(count, 2)
            XCTAssertLessThanOrEqual(count, 6)
        }
    }
}
#endif

@MainActor
class AsyncCountdownEventCancellationTests: XCTestCase {

    func testCancellation() async throws {
        let event = AsyncCountdownEvent(initial: 1)
        let task = Task.detached { try await event.wait() }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {}
    }

    func testAlreadyCancelledTask() async throws {
        let event = AsyncCountdownEvent(initial: 1)
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
