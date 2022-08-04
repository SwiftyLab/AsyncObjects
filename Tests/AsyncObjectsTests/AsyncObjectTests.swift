import XCTest
@testable import AsyncObjects

class AsyncObjectTests: XCTestCase {

    func testMultipleObjectWaitAll() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await event.signal()
            await mutex.signal()
        }
        await checkExecInterval(durationInSeconds: 5) {
            await waitForAll(event, mutex)
        }
    }

    func testMultipleObjectWaitAny() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await event.signal()
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await mutex.signal()
        }
        await checkExecInterval(durationInSeconds: 5) {
            await waitForAny(event, mutex)
        }
    }

    func testMultipleObjectWaitMultiple() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation(queue: .global(qos: .background)) {
            try await Task.sleep(nanoseconds: UInt64(5E9))
        }
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(2E9))
            await event.signal()
        }
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(3E9))
            await mutex.signal()
        }
        op.signal()
        await checkExecInterval(durationInSeconds: 3) {
            await waitForAny(event, mutex, op, count: 2)
        }
    }

    func testMultipleObjectWaitAllWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .success
        await checkExecInterval(durationInSeconds: 5) {
            result = await waitForAll(
                event, mutex,
                forNanoseconds: UInt64(5E9)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleObjectWaitAnyWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .success
        await checkExecInterval(durationInSeconds: 5) {
            result = await waitForAny(
                event, mutex,
                forNanoseconds: UInt64(5E9)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleObjectWaitMultipleWithTimeout() async throws {
        var result: TaskTimeoutResult = .success
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        let op = TaskOperation(queue: .global(qos: .background)) {
            try await Task.sleep(nanoseconds: UInt64(7E9))
        }
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(3E9))
            await event.signal()
        }
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await mutex.signal()
        }
        op.signal()
        await checkExecInterval(durationInSeconds: 4) {
            result = await waitForAny(
                event, mutex, op,
                count: 2,
                forNanoseconds: UInt64(4E9)
            )
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testMultipleObjectWaitAllWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await event.signal()
            await mutex.signal()
        }
        await checkExecInterval(durationInSeconds: 5) {
            result = await waitForAll(
                event, mutex,
                forNanoseconds: UInt64(10E9)
            )
        }
        XCTAssertEqual(result, .success)
    }

    func testMultipleObjectWaitAnyWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await event.signal()
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await mutex.signal()
        }
        await checkExecInterval(durationInSeconds: 5) {
            result = await waitForAny(
                event, mutex,
                forNanoseconds: UInt64(10E9)
            )
        }
        XCTAssertEqual(result, .success)
    }
}
