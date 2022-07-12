import XCTest
@testable import AsyncObject

class AsyncMutexTests: XCTestCase {

    func checkWait(
        for mutex: AsyncMutex,
        durationInSeconds seconds: Int = 0
    ) async throws {
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await mutex.release()
        }
        await checkExecInterval(
            for: { await mutex.wait() },
            durationInSeconds: seconds
        )
    }

    func testMutexWait() async throws {
        let mutex = AsyncMutex()
        try await checkWait(for: mutex, durationInSeconds: 5)
    }

    func testMutexLockAndWait() async throws {
        let mutex = AsyncMutex(lockedInitially: false)
        await mutex.lock()
        try await checkWait(for: mutex, durationInSeconds: 5)
    }

    func testReleasedMutexWait() async throws {
        let mutex = AsyncMutex(lockedInitially: false)
        try await checkWait(for: mutex)
    }

    func testMutexWaitWithTimeout() async throws {
        let mutex = AsyncMutex()
        var result: TaskTimeoutResult = .success
        await checkExecInterval(
            for: {
                result = await mutex.wait(forNanoseconds: UInt64(4E9))
            },
            durationInSeconds: 4
        )
        XCTAssertEqual(result, .timedOut)
    }

    func testMutexWaitSuccessWithoutTimeout() async throws {
        let mutex = AsyncMutex()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await mutex.release()
        }
        await checkExecInterval(
            for: {
                result = await mutex.wait(forNanoseconds: UInt64(10E9))
            },
            durationInSeconds: 5
        )
        XCTAssertEqual(result, .success)
    }

    func testReleasedMutexWaitSuccessWithoutTimeout() async throws {
        let mutex = AsyncMutex(lockedInitially: false)
        var result: TaskTimeoutResult = .timedOut
        await checkExecInterval(
            for: {
                result = await mutex.wait(forNanoseconds: UInt64(10E9))
            },
            durationInSeconds: 0
        )
        XCTAssertEqual(result, .success)
    }
}
