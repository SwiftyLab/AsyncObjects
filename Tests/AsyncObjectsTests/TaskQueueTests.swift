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
                try await self.sleep(seconds: 3)
            }
        }
        try await self.sleep(seconds: 1)
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
                    try await self.checkWaitOnQueue(option: option)
                }
            }
            try await group.waitForAll()
        }
    }

    func testTaskExecutionWithJustAddingTasks() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await self.sleep(seconds: 2)
        }
        // Make sure previous tasks started
        try await self.sleep(seconds: 0.001)
        try await self.checkExecInterval(durationInSeconds: 2) {
            queue.addTask { try! await self.sleep(seconds: 2) }
            try await queue.wait()
        }
    }

    func testDeinit() async throws {
        let queue = TaskQueue()
        try await queue.exec(flags: .barrier) {
            try await self.sleep(seconds: 1)
        }
        try await queue.exec {
            try await self.sleep(seconds: 1)
        }
        try await self.sleep(seconds: 0.001)
        self.addTeardownBlock { [weak queue] in
            try await self.sleep(seconds: 1)
            XCTAssertNil(queue)
        }
    }
}

@MainActor
class TaskQueueTimeoutTests: XCTestCase {

    private func checkWaitTimeoutOnQueue(
        option: TaskOption,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        let queue = TaskQueue(priority: option.queue)
        try await self.checkExecInterval(
            name: "For queue priority: \(option.queue.str), "
                + "task priority: \(option.task.str) "
                + "and flags: \(option.flags.rawValue)",
            durationInSeconds: 1,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(
                            priority: option.task,
                            flags: [option.flags, .block]
                        ) {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
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
                    try await self.checkWaitTimeoutOnQueue(option: option)
                }
            }
            try await group.waitForAll()
        }
    }

    #if swift(>=5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    private func checkWaitTimeoutOnQueue<C: Clock>(
        option: TaskOption,
        clock: C,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws where C.Duration == Duration {
        let queue = TaskQueue(priority: option.queue)
        try await self.checkExecInterval(
            name: "For queue priority: \(option.queue.str), "
                + "task priority: \(option.task.str) "
                + "and flags: \(option.flags.rawValue)",
            durationInSeconds: 1,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(
                            priority: option.task,
                            flags: [option.flags, .block]
                        ) {
                            continuation.resume()
                            try await self.sleep(seconds: 2, clock: clock)
                        }
                    }
                }
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
                    try await self.checkWaitTimeoutOnQueue(
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
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 2)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskBeforeOperation() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 1) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec {
                            continuation.resume()
                            try await self.sleep(seconds: 1)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterOperation() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(flags: .block) {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellation() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .block) {
            try await self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await self.checkExecInterval(durationInSeconds: 0) {
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
            try await self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await self.sleep(seconds: 5)
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
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 2)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block task
                    group.cancelAll()
                }
                try await queue.exec {
                    try await self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMultipleCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 3)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMixedeCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 4)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await self.sleep(seconds: 2)
                }
            }
        }
    }
}

@MainActor
class TaskQueueBarrierOperationTests: XCTestCase {

    func testExecutionOfTwoOperations() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskBeforeOperation() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterOperation() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(flags: .barrier) {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellation() async throws {
        let queue = TaskQueue()
        queue.addTask(flags: .barrier) {
            try await self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await self.checkExecInterval(durationInSeconds: 0) {
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
            try await self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await self.sleep(seconds: 5)
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
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 2)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block task
                    group.cancelAll()
                }
                try await queue.exec {
                    try await self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMultipleCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 2)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await self.sleep(seconds: 2)
                }
            }
        }
    }

    func testMixedCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 4)
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels block tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await self.sleep(seconds: 2)
                }
            }
        }
    }
}

@MainActor
class TaskQueueMixedOperationTests: XCTestCase {

    func testExecutionOfBlockTaskBeforeBarrierOperation() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(flags: .block) {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfBlockTaskAfterBarrierOperation() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(flags: .barrier) {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 1)
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
        try await self.checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec {
                            continuation.resume()
                            try await self.sleep(seconds: 2)
                        }
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await self.sleep(seconds: 1)
                    }
                }
                while let (_, c) = await Task(
                    priority: .background,
                    operation: {
                        let items = await queue.queue
                        return items.reversed().first
                    }
                ).value {
                    guard c.flags.contains(.block) else { continue }
                    break
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 3)
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
        await self.checkExecInterval(durationInSeconds: 6) {
            await withTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        await queue.exec {
                            continuation.resume()
                            try! await self.sleep(seconds: 3)
                        }
                    }
                }
                group.addTask {
                    await queue.exec(flags: .barrier) {
                        try! await self.sleep(seconds: 2)
                    }
                }
                while let (_, c) = await Task(
                    priority: .background,
                    operation: {
                        let items = await queue.queue
                        return items.reversed().first
                    }
                ).value {
                    guard c.flags.contains(.barrier) else { continue }
                    break
                }
                group.addTask {
                    await queue.exec(flags: .block) {
                        try! await self.sleep(seconds: 1)
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
        await self.checkExecInterval(durationInSeconds: 8) {
            await withTaskGroup(of: Void.self) { group in
                await withTaskGroup(of: Void.self) { cgroup in
                    for i in 0..<3 {
                        cgroup.addTask {
                            await waitForResume { continuation in
                                Task {
                                    await queue.exec {
                                        continuation.resume()
                                        try! await self.sleep(seconds: i + 1)
                                    }
                                }
                            }
                        }
                    }
                    await cgroup.waitForAll()
                }
                group.addTask {
                    await queue.exec(flags: .barrier) {
                        try! await self.sleep(seconds: 2)
                    }
                }
                while let (_, c) = await Task(
                    priority: .background,
                    operation: {
                        let items = await queue.queue
                        return items.reversed().first
                    }
                ).value {
                    guard c.flags.contains(.barrier) else { continue }
                    break
                }
                group.addTask {
                    await queue.exec {
                        try! await self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    await queue.exec {
                        try! await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    await queue.exec {
                        try! await self.sleep(seconds: 3)
                    }
                }
            }
        }
    }

    func testCancellableAndNonCancellableTasksWithBarrier() async throws {
        let queue = TaskQueue()
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                try await withThrowingTaskGroup(of: Void.self) { cgroup in
                    for i in 0..<3 {
                        cgroup.addTask {
                            await waitForResume { continuation in
                                Task {
                                    try await queue.exec {
                                        continuation.resume()
                                        try await self.sleep(seconds: i + 1)
                                    }
                                }
                            }
                        }
                    }
                    try await cgroup.waitForAll()
                }
                group.addTask {
                    try await queue.exec(flags: .barrier) {
                        try await self.sleep(seconds: 2)
                    }
                }
                while let (_, c) = await Task(
                    priority: .background,
                    operation: {
                        let items = await queue.queue
                        return items.reversed().first
                    }
                ).value {
                    guard c.flags.contains(.barrier) else { continue }
                    break
                }
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    await queue.exec {
                        do {
                            try await self.sleep(seconds: 3)
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
                            try await self.sleep(seconds: 4)
                            XCTFail("Unexpected task progression")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                while await Task(
                    priority: .background,
                    operation: {
                        return !(await queue.blocked)
                    }
                ).value {}
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
            try await self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await self.checkExecInterval(durationInSeconds: 0) {
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
            try await self.sleep(seconds: 10)
        }
        let task = Task.detached {
            try await self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await self.sleep(seconds: 5)
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
        await self.checkExecInterval(durationInSeconds: 0) {
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await self.sleep(seconds: 3)
                    }
                }
                group.addTask {
                    await queue.exec {
                        do {
                            try await self.sleep(seconds: 4)
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

    func checkWaitOnQueue(
        option: TaskOption,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        let queue = TaskQueue(priority: option.queue)
        try await self.checkExecInterval(
            name: "For queue priority: \(option.queue.str), "
                + "task priority: \(option.task.str) "
                + "and flags: \(option.flags.rawValue)",
            durationInSeconds: 1,
            file: file, function: function, line: line
        ) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await waitForResume { continuation in
                    group.addTask {
                        try await queue.exec(
                            priority: option.task,
                            flags: option.flags
                        ) {
                            continuation.resume()
                            try await self.sleep(seconds: 1)
                        }
                    }
                }
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
