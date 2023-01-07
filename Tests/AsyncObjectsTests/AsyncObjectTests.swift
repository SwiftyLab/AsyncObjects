import XCTest
@testable import AsyncObjects

@MainActor
class AsyncObjectTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore(value: 1)
        Task.detached { event.signal(); mutex.signal() }
        try await waitForTaskCompletion(withTimeoutInNanoseconds: UInt64(3E9)) {
            try await waitForAll(event, mutex)
        }
    }

    func testMultipleObjectWaitAny() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached { event.signal() }
        try await waitForTaskCompletion(withTimeoutInNanoseconds: UInt64(3E9)) {
            try await waitForAny(event, mutex)
        }
    }

    func testMultipleObjectWaitMultiple() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation { /* Do nothing */  }
        Task.detached { event.signal() }
        op.signal()
        try await waitForTaskCompletion(withTimeoutInNanoseconds: UInt64(3E9)) {
            try await waitForAny(event, mutex, op, count: 2)
        }
    }
}

@MainActor
class AsyncObjectTimeoutTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        do {
            try await waitForAll(event, mutex, forNanoseconds: UInt64(3E9))
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testMultipleObjectWaitAny() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        do {
            try await waitForAny(
                event, mutex,
                count: 2,
                forNanoseconds: UInt64(3E9)
            )
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testMultipleObjectWaitMultiple() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation { try await mutex.wait() }
        op.signal()
        Task.detached { event.signal() }
        do {
            try await waitForAny(
                event, mutex, op,
                count: 2,
                forNanoseconds: UInt64(3E9)
            )
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
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
        do {
            try await waitForAll(
                event, mutex,
                until: .now + .seconds(3),
                clock: clock
            )
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
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
        do {
            try await waitForAny(
                event, mutex,
                until: .now + .seconds(3),
                clock: clock
            )
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
    }

    func testMultipleObjectWaitMultiple() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation { try await mutex.wait() }
        op.signal()
        Task.detached { event.signal() }
        do {
            try await waitForAny(
                event, mutex, op,
                count: 2,
                until: .now + .seconds(3),
                clock: clock
            )
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
    }
}
#endif
