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

    func testMultipleObjectWaitAllWithTimeout() async throws {
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

    func testMultipleObjectWaitAnyWithTimeout() async throws {
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

    func testMultipleObjectWaitMultipleWithTimeout() async throws {
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

    func testMultipleObjectWaitAllWithoutTimeout() async throws {
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

    func testMultipleObjectWaitAnyWithoutTimeout() async throws {
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
}
