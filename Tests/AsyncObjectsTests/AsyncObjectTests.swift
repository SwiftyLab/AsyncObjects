import XCTest
@testable import AsyncObjects

@MainActor
class AsyncObjectTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
            await mutex.signal()
        }
        await Self.checkExecInterval(durationInSeconds: 1) {
            await waitForAll(event, mutex)
        }
    }

    func testMultipleObjectWaitAny() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
            try await Self.sleep(seconds: 1)
            await mutex.signal()
        }
        await Self.checkExecInterval(durationInSeconds: 1) {
            await waitForAny(event, mutex)
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
            await event.signal()
        }
        Task.detached {
            try await Self.sleep(seconds: 2)
            await mutex.signal()
        }
        op.signal()
        await Self.checkExecInterval(durationInSeconds: 2) {
            await waitForAny(event, mutex, op, count: 2)
        }
    }

    func testMultipleObjectWaitAllWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .success
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await waitForAll(
                event, mutex,
                forNanoseconds: UInt64(1E9)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleObjectWaitAnyWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .success
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await waitForAny(
                event, mutex,
                forNanoseconds: UInt64(1E9)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleObjectWaitMultipleWithTimeout() async throws {
        var result: TaskTimeoutResult = .success
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation {
            try await Self.sleep(seconds: 4)
        }
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
        }
        Task.detached {
            try await Self.sleep(seconds: 3)
            await mutex.signal()
        }
        op.signal()
        await Self.checkExecInterval(durationInSeconds: 2) {
            result = await waitForAny(
                event, mutex, op,
                count: 2,
                forNanoseconds: UInt64(2E9)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleObjectWaitAllWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
            await mutex.signal()
        }
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await waitForAll(
                event, mutex,
                forNanoseconds: UInt64(2E9)
            )
        }
        XCTAssertEqual(result, .success)
    }

    func testMultipleObjectWaitAnyWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Self.sleep(seconds: 1)
            await event.signal()
            try await Self.sleep(seconds: 1)
            await mutex.signal()
        }
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await waitForAny(
                event, mutex,
                forNanoseconds: UInt64(2E9)
            )
        }
        XCTAssertEqual(result, .success)
    }
}
