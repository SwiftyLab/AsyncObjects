import XCTest
@testable import AsyncObjects

@MainActor
class AsyncSemaphoreTests: XCTestCase {

    func checkSemaphoreWait(
        for semaphore: AsyncSemaphore,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = 1,
        durationInSeconds seconds: Int = 1
    ) async throws {
        try await Self.checkExecInterval(durationInSeconds: seconds) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        await semaphore.wait()
                        try await Self.sleep(seconds: delay)
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
        withDelay delay: UInt64 = 2,
        timeout: UInt64 = 1,
        durationInSeconds seconds: Int = 0
    ) async throws {
        let semaphore = AsyncSemaphore(value: value)
        let store = TaskTimeoutStore()
        try await Self.checkExecInterval(durationInSeconds: seconds) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        let result = await semaphore.wait(
                            forNanoseconds: timeout
                        )
                        result == .success
                            ? await store.addSuccess()
                            : await store.addFailure()
                        try await Self.sleep(seconds: delay)
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
        try await checkSemaphoreWait(for: semaphore, taskCount: 2)
    }

    func testSemaphoreWaitWithTasksEqualToCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await checkSemaphoreWait(for: semaphore, taskCount: 3)
    }

    func testSemaphoreWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await checkSemaphoreWait(
            for: semaphore,
            taskCount: 5,
            durationInSeconds: 2
        )
    }

    func testSignaledSemaphoreWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        await semaphore.signal()
        try await checkSemaphoreWait(
            for: semaphore,
            taskCount: 4,
            durationInSeconds: 2
        )
    }

    func testSemaphoreWaitTimeoutWithTasksLessThanCount() async throws {
        try await checkSemaphoreWaitWithTimeOut(
            taskCount: 3,
            timeout: 3,
            durationInSeconds: 2
        )
    }

    func testSemaphoreWaitTimeoutWithTasksGreaterThanCount() async throws {
        try await checkSemaphoreWaitWithTimeOut(
            taskCount: 5,
            timeout: 3,
            durationInSeconds: 2
        )
    }

    func testSemaphoreWaitWithZeroTimeout() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        var result: TaskTimeoutResult = .success
        await Self.checkExecInterval(durationInSeconds: 0) {
            result = await semaphore.wait(forNanoseconds: 0)
        }
        XCTAssertEqual(result, .success)
    }

    func testUsageAsMutexWaitWithTimeout() async throws {
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .success
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await mutex.wait(forSeconds: 1)
        }
        XCTAssertEqual(result, .timedOut)
    }

    func testUsageAsMutexWaitSuccessWithoutTimeout() async throws {
        let mutex = AsyncSemaphore()
        var result: TaskTimeoutResult = .timedOut
        Task.detached {
            try await Self.sleep(seconds: 1)
            await mutex.signal()
        }
        await Self.checkExecInterval(durationInSeconds: 1) {
            result = await mutex.wait(forSeconds: 2)
        }
        XCTAssertEqual(result, .success)
    }

    func testSemaphoreWaitCancellationWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await Self.checkExecInterval(durationInSeconds: 4) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<8 {
                    group.addTask {
                        if index <= 3 || index.isMultiple(of: 2) {
                            await semaphore.wait()
                            try await Self.sleep(seconds: 2)
                            await semaphore.signal()
                        } else {
                            let result = await semaphore.wait(forSeconds: 1)
                            XCTAssertEqual(result, .timedOut)
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testConcurrentMutation() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        let data = ArrayDataStore()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    await semaphore.wait()
                    data.add(index)
                    await semaphore.signal()
                }
            }
            await group.waitForAll()
        }
        XCTAssertEqual(data.items.count, 10)
    }

    func testDeinit() async throws {
        let semaphore = AsyncSemaphore()
        Task.detached {
            try await Self.sleep(seconds: 1)
            await semaphore.signal()
        }
        await semaphore.wait()
        self.addTeardownBlock { [weak semaphore] in
            XCTAssertNil(semaphore)
        }
    }

    func testWaitCancellationWhenTaskCancelled() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                await semaphore.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testWaitCancellationForAlreadyCancelledTask() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                await semaphore.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testConcurrentAccess() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let semaphore = AsyncSemaphore(value: 1)
                    await Self.checkExecInterval(durationInSeconds: 0) {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await semaphore.wait() }
                            group.addTask { await semaphore.signal() }
                            await group.waitForAll()
                        }
                    }
                }
                await group.waitForAll()
            }
        }
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

final class ArrayDataStore: @unchecked Sendable {
    var items: [Int] = []
    func add(_ item: Int) { items.append(item) }
}
