import XCTest
@testable import AsyncObjects

class AsyncEventTests: XCTestCase {

    func checkWait(
        for event: AsyncEvent,
        signalIn interval: UInt64 = UInt64(5E9),
        durationInSeconds seconds: Int = 0
    ) async throws {
        Task.detached {
            try await Task.sleep(nanoseconds: interval)
            await event.signal()
        }
        await checkExecInterval(durationInSeconds: seconds, for: event.wait)
    }

    func testEventWait() async throws {
        let event = AsyncEvent(signaledInitially: false)
        try await checkWait(for: event, durationInSeconds: 5)
    }

    func testEventLockAndWait() async throws {
        let event = AsyncEvent()
        await event.reset()
        try await checkWait(for: event, durationInSeconds: 5)
    }

    func testReleasedEventWait() async throws {
        let event = AsyncEvent()
        try await checkWait(for: event)
    }

    func testEventWaitWithTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        var result: TaskTimeoutResult = .success
        await checkExecInterval(durationInSeconds: 4) {
            result = await event.wait(forNanoseconds: UInt64(4E9))
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testEventWaitSuccessWithoutTimeout() async throws {
        let event = AsyncEvent(signaledInitially: false)
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await event.signal()
        }
        await checkExecInterval(durationInSeconds: 5) {
            result = await event.wait(forNanoseconds: UInt64(10E9))
        }
        XCTAssertEqual(result, .success)
    }

    func testReleasedEventWaitSuccessWithoutTimeout() async throws {
        let event = AsyncEvent()
        var result: TaskTimeoutResult = .timedOut
        await checkExecInterval(durationInSeconds: 0) {
            result = await event.wait(forNanoseconds: UInt64(10E9))
        }
        XCTAssertEqual(result, .success)
    }
}
