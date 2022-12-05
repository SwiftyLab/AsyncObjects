import XCTest
@testable import AsyncObjects

@MainActor
class AsyncCountdownEventTests: AsyncTestCase {

    func testWaitWithoutIncrement() async throws {
        let event = AsyncCountdownEvent()
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await event.wait()
        }
    }

    func testWaitWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Self.signalCountdownEvent(event, times: 10)
        try await Self.checkExecInterval(durationInSeconds: 5) {
            try await event.wait()
        }
    }

    func testWaitWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Self.signalCountdownEvent(event, times: 10)
        try await Self.checkExecInterval(durationInRange: 3.5..<4.3) {
            try await event.wait()
        }
    }

    func testWaitWithLimitInitialCountAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3, initial: 2)
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Self.signalCountdownEvent(event, times: 10)
        try await Self.checkExecInterval(durationInRange: 4.5..<5.3) {
            try await event.wait()
        }
    }

    func testWaitWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Task.detached {
            try await Self.sleep(seconds: 3)
            event.reset()
        }
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await event.wait()
        }
    }

    func testWaitWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Task.detached {
            try await Self.sleep(seconds: 3)
            event.reset(to: 2)
            Self.signalCountdownEvent(event, times: 10)
        }
        try await Self.checkExecInterval(durationInSeconds: 4) {
            try await event.wait()
        }
    }

    func testWaitWithConcurrentIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Task.detached {
            try await Self.sleep(seconds: 2)
            event.reset(to: 2)
        }
        Self.signalCountdownEvent(event, times: 10)
        try await Self.checkExecInterval(durationInRange: 2.5...3.2) {
            try await event.wait()
        }
    }

    func testDeinit() async throws {
        let event = AsyncCountdownEvent(until: 0, initial: 1)
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
                    let event = AsyncCountdownEvent(initial: 1)
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
class AsyncCountdownEventTimeoutTests: XCTestCase {

    func testWaitTimeoutWithIncrement() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 3) {
            do {
                try await event.wait(forSeconds: 3)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testWaitTimeoutWithLimitAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3)
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 2) {
            do {
                try await event.wait(forSeconds: 2)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testWaitTimeoutWithLimitInitialCountAndIncrement() async throws {
        let event = AsyncCountdownEvent(until: 3, initial: 3)
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(durationInSeconds: 3) {
            do {
                try await event.wait(forSeconds: 3)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testWaitTimeoutWithIncrementAndReset() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Task.detached {
            try await Self.sleep(seconds: 3)
            event.reset()
        }
        await Self.checkExecInterval(durationInSeconds: 2) {
            do {
                try await event.wait(forSeconds: 2)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testWaitTimeoutWithIncrementAndResetToCount() async throws {
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001)
        Task.detached {
            try await Self.sleep(seconds: 3)
            event.reset(to: 6)
            Self.signalCountdownEvent(event, times: 10)
        }
        await Self.checkExecInterval(durationInSeconds: 3) {
            do {
                try await event.wait(forSeconds: 3)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }
}

#if swift(>=5.7)
@MainActor
class AsyncCountdownEventClockTimeoutTests: XCTestCase {

    func testWaitTimeoutWithIncrement() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001, clock: clock)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(duration: .seconds(3), clock: clock) {
            do {
                try await event.wait(forSeconds: 3, clock: clock)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testWaitTimeoutWithLimitAndIncrement() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent(until: 3)
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001, clock: clock)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(duration: .seconds(2), clock: clock) {
            do {
                try await event.wait(forSeconds: 2, clock: clock)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testWaitTimeoutWithLimitInitialCountAndIncrement() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent(until: 3, initial: 3)
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001, clock: clock)
        Self.signalCountdownEvent(event, times: 10)
        await Self.checkExecInterval(duration: .seconds(3), clock: clock) {
            do {
                try await event.wait(forSeconds: 3, clock: clock)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testWaitTimeoutWithIncrementAndReset() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001, clock: clock)
        Task.detached {
            try await Self.sleep(seconds: 3, clock: clock)
            event.reset()
        }
        await Self.checkExecInterval(duration: .seconds(2), clock: clock) {
            do {
                try await event.wait(forSeconds: 2, clock: clock)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testWaitTimeoutWithIncrementAndResetToCount() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncCountdownEvent()
        event.increment(by: 10)
        try await Self.sleep(seconds: 0.001, clock: clock)
        Task.detached {
            try await Self.sleep(seconds: 3, clock: clock)
            event.reset(to: 6)
            Self.signalCountdownEvent(event, times: 10)
        }
        await Self.checkExecInterval(duration: .seconds(3), clock: clock) {
            do {
                try await event.wait(forSeconds: 3, clock: clock)
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
class AsyncCountdownEventCancellationTests: XCTestCase {

    func testWaitCancellation() async throws {
        let event = AsyncCountdownEvent(initial: 1)
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                try await event.wait()
            }
        }
        task.cancel()
        try? await task.value
    }

    func testAlreadyCancelledTask() async throws {
        let event = AsyncCountdownEvent(initial: 1)
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                try await event.wait()
            }
        }
        task.cancel()
        try? await task.value
    }
}

fileprivate extension XCTestCase {

    static func signalCountdownEvent(
        _ event: AsyncCountdownEvent,
        times count: UInt
    ) {
        Task.detached {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<count {
                    group.addTask {
                        try await Self.sleep(seconds: (Double(i) + 1) * 0.5)
                        event.signal(repeat: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}
