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
