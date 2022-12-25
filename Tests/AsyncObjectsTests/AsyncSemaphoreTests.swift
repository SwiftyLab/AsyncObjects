import XCTest
@testable import AsyncObjects

@MainActor
class AsyncSemaphoreTests: XCTestCase {

    func testWaitWithTasksLessThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await self.checkSemaphoreWait(for: semaphore, taskCount: 2)
    }

    func testWaitWithTasksEqualToCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await self.checkSemaphoreWait(for: semaphore, taskCount: 3)
    }

    func testWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await self.checkSemaphoreWait(
            for: semaphore,
            taskCount: 5,
            durationInSeconds: 2
        )
    }

    func testSignaledWaitWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        semaphore.signal()
        try await self.sleep(seconds: 0.001)
        try await self.checkSemaphoreWait(
            for: semaphore,
            taskCount: 4,
            durationInSeconds: 2
        )
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

    func testDeinit() async throws {
        let semaphore = AsyncSemaphore()
        Task.detached {
            try await self.sleep(seconds: 1)
            semaphore.signal()
        }
        try await semaphore.wait()
        self.addTeardownBlock { [weak semaphore] in
            try await self.sleep(seconds: 1)
            XCTAssertNil(semaphore)
        }
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let semaphore = AsyncSemaphore(value: 1)
                    try await self.checkExecInterval(durationInSeconds: 0) {
                        try await withThrowingTaskGroup(of: Void.self) {
                            group in
                            group.addTask { try await semaphore.wait() }
                            group.addTask { semaphore.signal() }
                            try await group.waitForAll()
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

@MainActor
class AsyncSemaphoreTimeoutTests: XCTestCase {

    func checkSemaphoreWaitWithTimeOut(
        value: UInt = 3,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = 2,
        timeout: UInt64 = 1,
        durationInSeconds seconds: Int = 0,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        let semaphore = AsyncSemaphore(value: value)
        try await self.checkExecInterval(
            durationInSeconds: seconds,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        let success: Bool
                        do {
                            try await semaphore.wait(forSeconds: timeout)
                            success = true
                        } catch {
                            success = false
                        }
                        try await self.sleep(seconds: delay)
                        if success { semaphore.signal() }
                        return success
                    }
                }

                var (successes, failures) = (0 as UInt, 0 as UInt)
                for try await success in group {
                    if success { successes += 1 } else { failures += 1 }
                }

                XCTAssertEqual(successes, value, file: file, line: line)
                XCTAssertEqual(
                    failures, UInt(count) - value,
                    file: file, line: line
                )
            }
        }
    }

    func testMutexWaitTimeout() async throws {
        let mutex = AsyncSemaphore()
        do {
            try await mutex.wait(forSeconds: 1)
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
        }
    }

    func testMutexWait() async throws {
        let mutex = AsyncSemaphore()
        Task.detached {
            try await self.sleep(seconds: 1)
            mutex.signal()
        }
        try await mutex.wait(forSeconds: 5)
    }

    func testWaitTimeoutWithTasksLessThanCount() async throws {
        try await self.checkSemaphoreWaitWithTimeOut(
            taskCount: 3,
            timeout: 3,
            durationInSeconds: 2
        )
    }

    func testWaitTimeoutWithTasksGreaterThanCount() async throws {
        try await self.checkSemaphoreWaitWithTimeOut(
            taskCount: 5,
            timeout: 1,
            durationInSeconds: 2
        )
    }

    func testWaitCancellationOnTimeoutWithTasksGreaterThanCount() async throws {
        let semaphore = AsyncSemaphore(value: 3)
        try await self.checkExecInterval(durationInSeconds: 4) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<8 {
                    group.addTask {
                        if index <= 3 || index.isMultiple(of: 2) {
                            try await semaphore.wait()
                            try await self.sleep(seconds: 2)
                            semaphore.signal()
                        } else {
                            do {
                                try await semaphore.wait(forSeconds: 1)
                                XCTFail("Unexpected task progression")
                            } catch {
                                XCTAssertTrue(
                                    type(of: error) == DurationTimeoutError.self
                                )
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

#if swift(>=5.7)
@MainActor
class AsyncSemaphoreClockTimeoutTests: XCTestCase {

    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    func checkSemaphoreWaitWithTimeOut<C: Clock>(
        value: UInt = 3,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = 2,
        timeout: UInt64 = 1,
        durationInSeconds seconds: Int = 0,
        clock: C,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws where C.Duration == Duration {
        let semaphore = AsyncSemaphore(value: value)
        try await self.checkExecInterval(
            durationInSeconds: seconds,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        let success: Bool
                        do {
                            try await semaphore.wait(
                                forSeconds: timeout,
                                clock: clock
                            )
                            success = true
                        } catch {
                            success = false
                        }
                        try await self.sleep(seconds: delay, clock: clock)
                        if success { semaphore.signal() }
                        return success
                    }
                }

                var (successes, failures) = (0 as UInt, 0 as UInt)
                for try await success in group {
                    if success { successes += 1 } else { failures += 1 }
                }

                XCTAssertEqual(successes, value, file: file, line: line)
                XCTAssertEqual(
                    failures, UInt(count) - value,
                    file: file, line: line
                )
            }
        }
    }

    func testMutexWaitTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let mutex = AsyncSemaphore()
        do {
            try await mutex.wait(forSeconds: 1, clock: clock)
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(
                type(of: error) == TimeoutError<ContinuousClock>.self
            )
        }
    }

    func testMutexWait() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let mutex = AsyncSemaphore()
        Task.detached {
            try await self.sleep(seconds: 1, clock: clock)
            mutex.signal()
        }
        try await mutex.wait(forSeconds: 5, clock: clock)
    }

    func testWaitTimeoutWithTasksLessThanCount() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        try await self.checkSemaphoreWaitWithTimeOut(
            taskCount: 3,
            timeout: 3,
            durationInSeconds: 2,
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
        try await self.checkSemaphoreWaitWithTimeOut(
            taskCount: 5,
            timeout: 1,
            durationInSeconds: 2,
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
        try await self.checkExecInterval(duration: .seconds(4), clock: clock) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<8 {
                    group.addTask {
                        if index <= 3 || index.isMultiple(of: 2) {
                            try await semaphore.wait()
                            try await self.sleep(seconds: 2, clock: clock)
                            semaphore.signal()
                        } else {
                            do {
                                try await semaphore.wait(
                                    forSeconds: 1,
                                    clock: clock
                                )
                                XCTFail("Unexpected task progression")
                            } catch {
                                XCTAssertTrue(
                                    type(of: error)
                                        == TimeoutError<ContinuousClock>.self
                                )
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}
#endif

@MainActor
class AsyncSemaphoreCancellationTests: XCTestCase {

    func testWaitCancellation() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task.detached {
            await self.checkExecInterval(durationInSeconds: 0) {
                try? await semaphore.wait()
            }
        }
        task.cancel()
        await task.value
    }

    func testAlreadyCancelledTask() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task.detached {
            await self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                try? await semaphore.wait()
            }
        }
        task.cancel()
        await task.value
    }
}

fileprivate extension XCTestCase {

    func checkSemaphoreWait(
        for semaphore: AsyncSemaphore,
        taskCount count: Int = 1,
        withDelay delay: UInt64 = 1,
        durationInSeconds seconds: Int = 1,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        try await self.checkExecInterval(
            durationInSeconds: seconds,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        try await semaphore.wait()
                        defer { semaphore.signal() }
                        try await self.sleep(seconds: delay)
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

final class ArrayDataStore: @unchecked Sendable {
    var items: [Int] = []
    func add(_ item: Int) { items.append(item) }
}
