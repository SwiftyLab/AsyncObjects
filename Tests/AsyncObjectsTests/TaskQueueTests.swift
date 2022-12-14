import XCTest
@testable import AsyncObjects

@MainActor
class TaskQueueTests: XCTestCase {

    func testSignalingDoesNothing() async {
        let queue = TaskQueue()
        queue.signal()
        let blocked = await queue.blocked
        XCTAssertFalse(blocked)
    }

    func testSignalingBlockedDoesNothing() async throws {
        let queue = TaskQueue()
        Task.detached {
            try await queue.exec(flags: .block) {
                try await Self.sleep(seconds: 3)
            }
        }
        try await Self.sleep(seconds: 1)
        queue.signal()
        let blocked = await queue.blocked
        XCTAssertTrue(blocked)
    }

    func testWait() async throws {
        let options: [TaskOption] = [
            (queue: nil, task: nil, flags: []),
            (queue: nil, task: .high, flags: []),
            (queue: nil, task: .high, flags: .enforce),
            (queue: nil, task: nil, flags: .detached),
            (queue: nil, task: .high, flags: [.enforce, .detached]),
            (queue: .high, task: nil, flags: []),
            (queue: .high, task: .high, flags: []),
            (queue: .high, task: .high, flags: .enforce),
            (queue: .high, task: nil, flags: .detached),
            (queue: .high, task: .high, flags: [.enforce, .detached]),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            options.forEach { option in
                group.addTask {
                    try await Self.checkWaitOnQueue(option: option)
                }
            }
            try await group.waitForAll()
        }
    }

    func testTaskExecutionWithJustAddingTasks() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await Self.sleep(seconds: 2)
        }
        // Make sure previous tasks started
        try await Self.sleep(seconds: 0.001)
        try await Self.checkExecInterval(durationInSeconds: 2) {
            queue.addTask { try! await Self.sleep(seconds: 2) }
            try await queue.wait()
        }
    }

    func testDeinit() async throws {
        let queue = TaskQueue()
        try await queue.exec(flags: .barrier) {
            try await Self.sleep(seconds: 1)
        }
        try await queue.exec {
            try await Self.sleep(seconds: 1)
        }
        try await Self.sleep(seconds: 0.001)
        self.addTeardownBlock { [weak queue] in
            try await Self.sleep(seconds: 1)
            XCTAssertNil(queue)
        }
    }
}

@MainActor
class TaskQueueTimeoutTests: XCTestCase {

    private static func checkWaitTimeoutOnQueue(
        option: TaskOption,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        let queue = TaskQueue(priority: option.queue)
        try await Self.checkExecInterval(
            name: "For queue priority: \(option.queue.str), "
                + "task priority: \(option.task.str) "
                + "and flags: \(option.flags.rawValue)",
            durationInSeconds: 1,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(
                        priority: option.task,
                        flags: [option.flags, .block]
                    ) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    do {
                        try await queue.wait(forSeconds: 1)
                        XCTFail(
                            "Unexpected task progression",
                            file: file, line: line
                        )
                    } catch {
                        XCTAssertTrue(
                            type(of: error) == DurationTimeoutError.self,
                            file: file, line: line
                        )
                    }
                }
                for try await _ in group.prefix(1) {
                    group.cancelAll()
                }
            }
        }
    }

    func testWaitTimeout() async throws {
        let options: [TaskOption] = [
            (queue: nil, task: nil, flags: []),
            (queue: nil, task: .high, flags: []),
            (queue: nil, task: .high, flags: .enforce),
            (queue: nil, task: nil, flags: .detached),
            (queue: nil, task: .high, flags: [.enforce, .detached]),
            (queue: .high, task: nil, flags: []),
            (queue: .high, task: .high, flags: []),
            (queue: .high, task: .high, flags: .enforce),
            (queue: .high, task: nil, flags: .detached),
            (queue: .high, task: .high, flags: [.enforce, .detached]),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            options.forEach { option in
                group.addTask {
                    try await Self.checkWaitTimeoutOnQueue(option: option)
                }
            }
            try await group.waitForAll()
        }
    }

    #if swift(>=5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    private static func checkWaitTimeoutOnQueue<C: Clock>(
        option: TaskOption,
        clock: C,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws where C.Duration == Duration {
        let queue = TaskQueue(priority: option.queue)
        try await Self.checkExecInterval(
            name: "For queue priority: \(option.queue.str), "
                + "task priority: \(option.task.str) "
                + "and flags: \(option.flags.rawValue)",
            durationInSeconds: 1,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(
                        priority: option.task,
                        flags: [option.flags, .block]
                    ) {
                        try await Self.sleep(seconds: 2, clock: clock)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01, clock: clock)
                group.addTask {
                    do {
                        try await queue.wait(forSeconds: 1, clock: clock)
                        XCTFail(
                            "Unexpected task progression",
                            file: file, line: line
                        )
                    } catch {
                        XCTAssertTrue(
                            type(of: error)
                                == TimeoutError<ContinuousClock>.self,
                            file: file, line: line
                        )
                    }
                }
                for try await _ in group.prefix(1) {
                    group.cancelAll()
                }
            }
        }
    }

    func testWaitClockTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let options: [TaskOption] = [
            (queue: nil, task: nil, flags: []),
            (queue: nil, task: .high, flags: []),
            (queue: nil, task: .high, flags: .enforce),
            (queue: nil, task: nil, flags: .detached),
            (queue: nil, task: .high, flags: [.enforce, .detached]),
            (queue: .high, task: nil, flags: []),
            (queue: .high, task: .high, flags: []),
            (queue: .high, task: .high, flags: .enforce),
            (queue: .high, task: nil, flags: .detached),
            (queue: .high, task: .high, flags: [.enforce, .detached]),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            options.forEach { option in
                group.addTask {
                    try await Self.checkWaitTimeoutOnQueue(
                        option: option,
                        clock: clock
                    )
                }
            }
            try await group.waitForAll()
        }
    }
    #endif
}

@MainActor
class TaskQueueBlockOperationTests: XCTestCase {

    func testExecutionOfTwoOperations() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskBeforeOperation() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterOperation() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellation() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .block) {
            try await Self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                await queue.exec(flags: .block) {}
                try await queue.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testAlreadyCancelledTask() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .block) {
            try await Self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                await queue.exec(flags: .block) {}
                try await queue.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block task
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMultipleCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 3)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMixedeCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 4)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Self.sleep(seconds: 2)
                }
            }
        }
    }
}

@MainActor
class TaskQueueBarrierOperationTests: XCTestCase {

    func testExecutionOfTwoOperations() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskBeforeOperation() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterOperation() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellation() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await Self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                await queue.exec(flags: .barrier) {}
                try await queue.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testAlreadyCancelledTask() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await Self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                await queue.exec(flags: .barrier) {}
                try await queue.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block task
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMultipleCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMixedCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 4)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Self.sleep(seconds: 2)
                }
            }
        }
    }
}

@MainActor
class TaskQueueMixedOperationTests: XCTestCase {

    func testExecutionOfBlockTaskBeforeBarrierOperation() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfBlockTaskAfterBarrierOperation() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testLongRunningConcurrentTaskWithShortBlockTaskBeforeBarrierOperation()
        async throws
    {
        let queue = TaskQueue()
        // Concurrent + Barrier
        try await Self.checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                await group.addTaskAndStart {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                await group.addTaskAndStart {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 3)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testLongRunningConcurrentTaskWithShortBlockTaskAfterBarrierOperation()
        async throws
    {
        let queue = TaskQueue()
        // Concurrent + Barrier + Block
        await Self.checkExecInterval(durationInSeconds: 6) {
            await withTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await queue.exec {
                        try! await Self.sleep(seconds: 3)
                    }
                }
                // Make sure previous tasks started
                try! await Self.sleep(seconds: 0.01)
                await group.addTaskAndStart {
                    await queue.exec(flags: .barrier) {
                        try! await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try! await Self.sleep(seconds: 0.01)
                await group.addTaskAndStart {
                    await queue.exec(flags: .block) {
                        try! await Self.sleep(seconds: 1)
                    }
                }
                await group.waitForAll()
            }
        }
    }

    /// Scenario described in:
    /// https://forums.swift.org/t/concurrency-suspending-an-actor-async-func-until-the-actor-meets-certain-conditions/56580
    func testBarrierTaskWithMultipleConcurrentTasks() async throws {
        let queue = TaskQueue()
        await Self.checkExecInterval(durationInSeconds: 8) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await queue.exec {
                        try! await Self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    await queue.exec {
                        try! await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    await queue.exec {
                        try! await Self.sleep(seconds: 3)
                    }
                }
                // Make sure previous tasks started
                try! await Self.sleep(seconds: 0.01)
                await group.addTaskAndStart {
                    await queue.exec(flags: .barrier) {
                        try! await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try! await Self.sleep(seconds: 0.01)
                group.addTask {
                    await queue.exec {
                        try! await Self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    await queue.exec {
                        try! await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    await queue.exec {
                        try! await Self.sleep(seconds: 3)
                    }
                }
            }
        }
    }

    func testCancellableAndNonCancellableTasksWithBarrier() async throws {
        let queue = TaskQueue()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 3)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                await group.addTaskAndStart {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    await queue.exec {
                        do {
                            try await Self.sleep(seconds: 3)
                            XCTFail("Unexpected task progression")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                group.addTask {
                    await queue.exec {
                        do {
                            try await Self.sleep(seconds: 4)
                            XCTFail("Unexpected task progression")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }

                for _ in 0..<3 { try await group.next() }
                group.cancelAll()
            }
        }
    }
}

@MainActor
class TaskQueueCancellationTests: XCTestCase {

    func testWaitCancellation() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await Self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                try await queue.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testAlreadyCancelledTask() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await Self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                try await queue.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testCancellableAndNonCancellableTasks() async throws {
        let queue = TaskQueue()
        await Self.checkExecInterval(durationInSeconds: 0) {
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    await queue.exec {
                        do {
                            try await Self.sleep(seconds: 4)
                            XCTFail("Unexpected task progression")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                group.cancelAll()
            }
        }
    }
}

fileprivate extension XCTestCase {
    typealias TaskOption = (
        queue: TaskPriority?, task: TaskPriority?, flags: TaskQueue.Flags
    )

    static func checkWaitOnQueue(
        option: TaskOption,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        let queue = TaskQueue(priority: option.queue)
        try await Self.checkExecInterval(
            name: "For queue priority: \(option.queue.str), "
                + "task priority: \(option.task.str) "
                + "and flags: \(option.flags.rawValue)",
            durationInSeconds: 1,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(
                        priority: option.task,
                        flags: option.flags
                    ) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask { try await queue.wait() }
                try await group.waitForAll()
            }
        }
    }
}

extension Optional where Wrapped == TaskPriority {
    var str: String {
        switch self {
        case .none:
            return "none"
        case .some(let wrapped):
            return "\(wrapped.rawValue)"
        }
    }
}
