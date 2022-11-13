import XCTest
@testable import AsyncObjects

@MainActor
class AsyncObjectTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
            mutex.signal()
        }
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await waitForAll(event, mutex)
        }
    }

    func testMultipleObjectWaitAny() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
            try await Self.sleep(seconds: 1)
            mutex.signal()
        }
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await waitForAny(event, mutex)
        }
    }

    func testMultipleObjectWaitMultiple() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation {
            try await Self.sleep(seconds: 3)
        }
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
        }
        Task.detached {
            try await Self.sleep(seconds: 2)
            mutex.signal()
        }
        op.signal()
        try await Self.checkExecInterval(durationInSeconds: 2) {
            try await waitForAny(event, mutex, op, count: 2)
        }
    }
}

@MainActor
class AsyncObjectTimeoutTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
            mutex.signal()
        }
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await waitForAll(
                event, mutex,
                forNanoseconds: UInt64(2E9)
            )
        }
    }

    func testMultipleObjectWaitAny() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
            try await Self.sleep(seconds: 1)
            mutex.signal()
        }
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await waitForAny(
                event, mutex,
                forNanoseconds: UInt64(2E9)
            )
        }
    }

    func testMultipleObjectWaitAllTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        await Self.checkExecInterval(durationInSeconds: 1) {
            do {
                try await waitForAll(
                    event, mutex,
                    forNanoseconds: UInt64(1E9)
                )
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testMultipleObjectWaitAnyTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        await Self.checkExecInterval(durationInSeconds: 1) {
            do {
                try await waitForAny(
                    event, mutex,
                    count: 2,
                    forNanoseconds: UInt64(1E9)
                )
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testMultipleObjectWaitMultipleTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation {
            try await Self.sleep(seconds: 4)
        }
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
        }
        Task.detached {
            try await Self.sleep(seconds: 3)
            mutex.signal()
        }
        op.signal()
        await Self.checkExecInterval(durationInSeconds: 2) {
            do {
                try await waitForAny(
                    event, mutex, op,
                    count: 2,
                    forNanoseconds: UInt64(2E9)
                )
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }
}

#if swift(>=5.7)
@MainActor
class AsyncObjectClockTimeoutTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
            mutex.signal()
        }
        try await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            try await waitForAll(
                event, mutex,
                until: .now + .seconds(2),
                clock: clock
            )
        }
    }

    func testMultipleObjectWaitAny() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
            try await Self.sleep(seconds: 1)
            mutex.signal()
        }
        try await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            try await waitForAny(
                event, mutex,
                until: .now + .seconds(2),
                clock: clock
            )
        }
    }

    func testMultipleObjectWaitAllTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            do {
                try await waitForAll(
                    event, mutex,
                    until: .now + .seconds(1),
                    clock: clock
                )
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testMultipleObjectWaitAnyTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            do {
                try await waitForAny(
                    event, mutex,
                    count: 2,
                    until: .now + .seconds(1),
                    clock: clock
                )
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testMultipleObjectWaitMultipleTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation {
            try await Self.sleep(seconds: 4)
        }
        Task.detached {
            try await Self.sleep(seconds: 1)
            event.signal()
        }
        Task.detached {
            try await Self.sleep(seconds: 3)
            mutex.signal()
        }
        op.signal()
        await Self.checkExecInterval(duration: .seconds(2), clock: clock) {
            do {
                try await waitForAny(
                    event, mutex, op,
                    count: 2,
                    until: .now + .seconds(2),
                    clock: clock
                )
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
