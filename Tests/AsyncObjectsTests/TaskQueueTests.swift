import XCTest
@testable import AsyncObjects

class TaskQueueTests: XCTestCase {
    typealias TaskOption = (
        queue: TaskPriority?, task: TaskPriority?, flags: TaskQueue.Flags
    )

    func testSignalingQueueDoesNothing() async {
        let queue = TaskQueue()
        await queue.signal()
        let blocked = await queue.blocked
        XCTAssertFalse(blocked)
    }

    func testSignalingLockedQueueDoesNothing() async throws {
        let queue = TaskQueue()
        Task.detached {
            try await queue.exec(flags: .block) {
                try await Self.sleep(seconds: 3)
            }
        }
        try await Self.sleep(seconds: 1)
        await queue.signal()
        let blocked = await queue.blocked
        XCTAssertTrue(blocked)
    }

    func checkWaitOnQueue(option: TaskOption) async throws {
        let queue = TaskQueue(priority: option.queue)
        try await checkExecInterval(durationInSeconds: 1) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(
                        priority: option.task,
                        flags: option.flags
                    ) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                group.addTask { await queue.wait() }
                try await group.waitForAll()
            }
        }
    }

    func testWaitOnQueue() async throws {
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

    func checkWaitTimeoutOnQueue(option: TaskOption) async throws {
        let queue = TaskQueue(priority: option.queue)
        try await checkExecInterval(durationInSeconds: 1) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(
                        priority: option.task,
                        flags: [option.flags, .block]
                    ) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask { await queue.wait(forSeconds: 1) }
                for try await _ in group.prefix(1) {
                    group.cancelAll()
                }
            }
        }
    }

    func testWaitTimeoutOnQueue() async throws {
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

    func testExecutionOfTwoBlockOperations() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
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

    func testExecutionOfTaskBeforeBlockOperation() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 1) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                group.addTask {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterBlockOperation() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellationOfBlockTaskWithoutBlockingQueue() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
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

    func testCancellationOfMultipleBlockTasksWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
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

    func
        testCancellationOfMultipleBlockTasksAndOneConcurrentTaskWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
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

    func testExecutionOfTwoBarrierOperations() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
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

    func testExecutionOfTaskBeforeBarrierOperation() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec {
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

    func testExecutionOfTaskAfterBarrierOperation() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Self.sleep(seconds: 1)
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellationOfBarrierTaskWithoutBlockingQueue() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
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

    func testCancellationOfMultipleBarrierTasksWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
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

    func
        testCancellationOfMultipleBarrierTasksAndOneConcurrentTaskWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.sleep(seconds: 1)
                    // Throws error for waiting method
                    throw CancellationError()
                }
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

    func testExecutionOfBlockTaskBeforeBarrierOperation() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .block) {
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

    func testExecutionOfBlockTaskAfterBarrierOperation() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec(flags: .barrier) {
                        try await Self.sleep(seconds: 2)
                    }
                }
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
        try await checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await queue.exec {
                        try await Self.sleep(seconds: 2)
                    }
                }
                await group.addTaskAndStart {
                    try await queue.exec(flags: .block) {
                        try await Self.sleep(seconds: 1)
                    }
                }
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
        await checkExecInterval(durationInSeconds: 6) {
            await withTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await queue.exec {
                        try! await Self.sleep(seconds: 3)
                    }
                }
                await group.addTaskAndStart {
                    await queue.exec(flags: .barrier) {
                        try! await Self.sleep(seconds: 2)
                    }
                }
                await group.addTaskAndStart {
                    await queue.exec(flags: .block) {
                        try! await Self.sleep(seconds: 1)
                    }
                }
                await group.waitForAll()
            }
        }
    }
}
