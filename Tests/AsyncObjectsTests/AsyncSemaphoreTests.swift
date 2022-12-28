import XCTest
@testable import AsyncObjects

@MainActor
class AsyncSemaphoreTests: XCTestCase {

    func testWithTasksLessThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        await semaphore.spinTasks(count: 2, duration: 10)
        try await semaphore.wait(forSeconds: 3)
    }

    func testWithTasksEqualToCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        await semaphore.spinTasks(count: 3, duration: 10)
        do {
            try await semaphore.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        await semaphore.spinTasks(count: 5, duration: 10)
        do {
            try await semaphore.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testSignaledWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        await semaphore.signalSemaphore()
        await semaphore.spinTasks(count: 4, duration: 10)
        do {
            try await semaphore.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testConcurrentMutation() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        let data = ArrayDataStore()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    try await semaphore.wait()
                    data.add(index)
                    semaphore.signal()
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(data.items.count, 10)
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let semaphore = AsyncSemaphore(value: 1)
                    try await withThrowingTaskGroup(of: Void.self) { g in
                        g.addTask { try await semaphore.wait(forSeconds: 3) }
                        g.addTask { semaphore.signal() }
                        try await g.waitForAll()
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testDeinit() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        try await semaphore.wait(forSeconds: 3)
        self.addTeardownBlock { [weak semaphore] in
            XCTAssertEqual(semaphore.retainCount(), 0)
        }
    }
}

@MainActor
class AsyncSemaphoreTimeoutTests: XCTestCase {

    func testMutexWaitTimeout() async throws {
        let mutex = AsyncSemaphore()
        do {
            try await mutex.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }

    func testWaitTimeoutWithTasksLessThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await semaphore.spinTasks(count: 3, duration: 2, timeout: 3)
    }

    func testWaitTimeoutWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await semaphore.spinTasks(count: 5, duration: 5, timeout: 3)
    }

    func testWaitCancellationOnTimeoutWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    if index <= 3 || index.isMultiple(of: 2) {
                        try await semaphore.wait()
                        try await Task.sleep(seconds: 5)
                        semaphore.signal()
                    } else {
                        do {
                            try await semaphore.wait(forSeconds: 3)
                            XCTFail("Unexpected task progression")
                        } catch is DurationTimeoutError {}
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}

#if swift(>=5.7)
@MainActor
class AsyncSemaphoreClockTimeoutTests: XCTestCase {

    func testMutexWaitTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let mutex = AsyncSemaphore()
        do {
            try await mutex.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
    }

    func testWaitTimeoutWithTasksLessThanCount() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let semaphore = AsyncSemaphore(value: 3)
        try await semaphore.spinTasks(
            count: 3, duration: 2, timeout: 3,
            clock: clock
        )
    }

    func testWaitTimeoutWithTasksGreaterThanCount() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let semaphore = AsyncSemaphore(value: 3)
        try await semaphore.spinTasks(
            count: 5, duration: 5, timeout: 3,
            clock: clock
        )
    }

    func testWaitCancellationOnTimeoutWithTasksGreaterThanCount() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let semaphore = AsyncSemaphore(value: 3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    if index <= 3 || index.isMultiple(of: 2) {
                        try await semaphore.wait()
                        try await Task.sleep(seconds: 5, clock: clock)
                        semaphore.signal()
                    } else {
                        do {
                            try await semaphore.wait(
                                forSeconds: 3, clock: clock)
                            XCTFail("Unexpected task progression")
                        } catch is TimeoutError<ContinuousClock> {}
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
#endif

@MainActor
class AsyncSemaphoreCancellationTests: XCTestCase {

    func testWaitCancellation() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task.detached { try await semaphore.wait() }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {}
    }

    func testAlreadyCancelledTask() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 5)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            try await semaphore.wait()
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {}
    }
}

final class ArrayDataStore: @unchecked Sendable {
    var items: [Int] = []
    func add(_ item: Int) { items.append(item) }
}

fileprivate extension AsyncSemaphore {

    func spinTasks(count: UInt, duration: UInt64) async {
        let stream = AsyncStream<Void> { continuation in
            for _ in 0..<count {
                Task {
                    try await self.wait()
                    defer { self.signal() }
                    continuation.yield()
                    try await Task.sleep(seconds: duration)
                }
            }
        }

        var index = 0
        for await _ in stream {
            index += 1
            guard index < min(count, limit) else { continue }
            break
        }
    }

    func spinTasks(
        count: UInt, duration: UInt64, timeout: UInt64,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<count {
                group.addTask {
                    let success: Bool
                    do {
                        try await self.wait(forSeconds: timeout)
                        success = true
                    } catch {
                        success = false
                    }
                    try await Task.sleep(seconds: duration)
                    if success { self.signal() }
                    return success
                }
            }

            var (successes, failures) = (0 as UInt, 0 as UInt)
            for try await success in group {
                if success { successes += 1 } else { failures += 1 }
            }

            XCTAssertEqual(successes, limit - 1, file: file, line: line)
            XCTAssertEqual(failures, count + 1 - limit, file: file, line: line)
        }
    }

    #if swift(>=5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    func spinTasks<C: Clock>(
        count: UInt, duration: UInt64, timeout: UInt64, clock: C,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws where C.Duration == Duration {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<count {
                group.addTask {
                    let success: Bool
                    do {
                        try await self.wait(forSeconds: timeout, clock: clock)
                        success = true
                    } catch {
                        success = false
                    }
                    try await Task.sleep(seconds: duration, clock: clock)
                    if success { self.signal() }
                    return success
                }
            }

            var (successes, failures) = (0 as UInt, 0 as UInt)
            for try await success in group {
                if success { successes += 1 } else { failures += 1 }
            }

            XCTAssertEqual(successes, limit - 1, file: file, line: line)
            XCTAssertEqual(failures, count + 1 - limit, file: file, line: line)
        }
    }
    #endif
}
