import XCTest
@testable import AsyncObjects

class AsyncSemaphoreTests: XCTestCase {

    func checkSemaphoreWait(
        for semaphore: AsyncSemaphore,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = UInt64(5E9),
        durationInSeconds seconds: Int = 0
    ) async throws {
        try await checkExecInterval(durationInSeconds: seconds) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        await semaphore.wait()
                        try await Task.sleep(nanoseconds: delay)
                        await semaphore.signal()
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func checkSemaphoreWaitWithTimeOut(
        value: UInt = 3,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = UInt64(5E9),
        timeout: UInt64 = UInt64(3E9),
        durationInSeconds seconds: Int = 0
    ) async throws {
        let semaphore = AsyncSemaphore(value: value)
        let store = TaskTimeoutStore()
        try await checkExecInterval(durationInSeconds: seconds) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        let result = await semaphore.wait(
                            forNanoseconds: timeout)
                        result == .success
                            ? await store.addSuccess()
                            : await store.addFailure()
                        try await Task.sleep(nanoseconds: delay)
                        await semaphore.signal()
                    }
                }
                try await group.waitForAll()
            }
        }
        let (successes, failures) = (
            await store.successes, await store.failures
        )
        XCTAssertEqual(successes, value)
        XCTAssertEqual(failures, UInt(count) - value)
    }

    func testSemaphoreWaitWithTasksLessThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await checkSemaphoreWait(
            for: semaphore,
            taskCount: 2,
            durationInSeconds: 5
        )
    }

    func testSemaphoreWaitWithTasksEqualToCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await checkSemaphoreWait(
            for: semaphore,
            taskCount: 3,
            durationInSeconds: 5
        )
    }

    func testSemaphoreWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await checkSemaphoreWait(
            for: semaphore,
            taskCount: 5,
            durationInSeconds: 10
        )
    }

    func testSignaledSemaphoreWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        await semaphore.signal()
        try await checkSemaphoreWait(
            for: semaphore,
            taskCount: 4,
            durationInSeconds: 10
        )
    }

    func testSemaphoreWaitTimeoutWithTasksLessThanCount() async throws {
        try await checkSemaphoreWaitWithTimeOut(
            taskCount: 3,
            timeout: UInt64(3E9),
            durationInSeconds: 5
        )
    }

    func testSemaphoreWaitTimeoutWithTasksGreaterThanCount() async throws {
        try await checkSemaphoreWaitWithTimeOut(
            taskCount: 5,
            timeout: UInt64(3E9),
            durationInSeconds: 8
        )
    }

    func testSemaphoreWaitWithZeroTimeout() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        var result: TaskTimeoutResult = .success
        await checkExecInterval(durationInSeconds: 0) {
            result = await semaphore.wait(forNanoseconds: 0)
        }
        XCTAssertEqual(result, .success)
    }

    func testUsageAsMutexWaitWithTimeout() async throws {
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .success
        await checkExecInterval(durationInSeconds: 4) {
            result = await mutex.wait(forNanoseconds: UInt64(4E9))
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testUsageAsMutexWaitSuccessWithoutTimeout() async throws {
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Task.sleep(nanoseconds: UInt64(5E9))
            await mutex.signal()
        }
        await checkExecInterval(durationInSeconds: 5) {
            result = await mutex.wait(forNanoseconds: UInt64(10E9))
        }
        XCTAssertEqual(result, .success)
    }
}

actor TaskTimeoutStore {
    var successes: UInt = 0
    var failures: UInt = 0

    func addSuccess() {
        successes += 1
    }

    func addFailure() {
        failures += 1
    }
}
