import XCTest
@testable import AsyncObject

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

class AsyncSemaphoreTests: XCTestCase {

    func checkSemaphoreWait(
        for semaphore: AsyncSemaphore,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = UInt64(5E9),
        durationInSeconds seconds: Int = 0
    ) async throws {
        try await checkExecInterval(
            for: {
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
            }, durationInSeconds: seconds)
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
        try await checkExecInterval(
            for: {
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
            }, durationInSeconds: seconds)
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
}
