import XCTest
@testable import AsyncObjects

class TaskQueueTests: XCTestCase {

    func testSignalingQueueDoesNothing() async {
        let queue = TaskQueue()
        await queue.signal()
        let barriered = await queue.barriered
        XCTAssertFalse(barriered)
    }

    func testSignalingLockedQueueDoesNothing() async throws {
        let queue = TaskQueue()
        Task.detached {
            try await queue.exec(barrier: true) {
                try await Task.sleep(nanoseconds: UInt64(5E9))
            }
        }
        try await Task.sleep(nanoseconds: UInt64(1E9))
        await queue.signal()
        let barriered = await queue.barriered
        XCTAssertTrue(barriered)
    }

    func checkWaitOnQueue(priorities: [TaskQueue.Priority]) async throws {
        let queue = TaskQueue(priority: priorities[0])
        try await checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(
                        barrier: true,
                        priority: priorities[1]
                    ) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task started before wait
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask { await queue.wait() }
                try await group.waitForAll()
            }
        }
    }

    func testWaitOnQueue() async throws {
        let prioritiesMatrix: [[TaskQueue.Priority]] = [
            [.none, .none],
            [.none, .inherit],
            [.none, .enforce(.high)],
            [.none, .detached()],
            [.none, .detached(.high)],
            [.inherit, .none],
            [.inherit, .inherit],
            [.inherit, .enforce(.high)],
            [.inherit, .detached()],
            [.inherit, .detached(.high)],
            [.enforce(.high), .none],
            [.enforce(.high), .inherit],
            [.enforce(.high), .enforce(.high)],
            [.enforce(.high), .detached()],
            [.enforce(.high), .detached(.high)],
            [.detached(), .none],
            [.detached(), .inherit],
            [.detached(), .enforce(.high)],
            [.detached(), .detached()],
            [.detached(), .detached(.high)],
            [.detached(.high), .none],
            [.detached(.high), .inherit],
            [.detached(.high), .enforce(.high)],
            [.detached(.high), .detached()],
            [.detached(.high), .detached(.high)],
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            prioritiesMatrix.forEach { priorities in
                group.addTask {
                    try await self.checkWaitOnQueue(priorities: priorities)
                }
            }
            try await group.waitForAll()
        }
    }

    func checkWaitTimeoutOnQueue(
        priorities: [TaskQueue.Priority]
    ) async throws {
        let queue = TaskQueue(priority: priorities[0])
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(
                        barrier: true,
                        priority: priorities[1]
                    ) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task started before wait
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask { await queue.wait(forNanoseconds: UInt64(3E9)) }
                for try await _ in group.prefix(1) {
                    group.cancelAll()
                }
            }
        }
    }

    func testWaitTimeoutOnQueue() async throws {
        let prioritiesMatrix: [[TaskQueue.Priority]] = [
            [.none, .none],
            [.none, .inherit],
            [.none, .enforce(.high)],
            [.none, .detached()],
            [.none, .detached(.high)],
            [.inherit, .none],
            [.inherit, .inherit],
            [.inherit, .enforce(.high)],
            [.inherit, .detached()],
            [.inherit, .detached(.high)],
            [.enforce(.high), .none],
            [.enforce(.high), .inherit],
            [.enforce(.high), .enforce(.high)],
            [.enforce(.high), .detached()],
            [.enforce(.high), .detached(.high)],
            [.detached(), .none],
            [.detached(), .inherit],
            [.detached(), .enforce(.high)],
            [.detached(), .detached()],
            [.detached(), .detached(.high)],
            [.detached(.high), .none],
            [.detached(.high), .inherit],
            [.detached(.high), .enforce(.high)],
            [.detached(.high), .detached()],
            [.detached(.high), .detached(.high)],
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            prioritiesMatrix.forEach { priorities in
                group.addTask {
                    try await self.checkWaitTimeoutOnQueue(
                        priorities: priorities
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    func testExecutionOfTwoBarriers() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 10) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskBeforeBarrier() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task added after concurrent task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterBarrier() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 10) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task started before adding new task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellationOfBarrierTaskWithoutBlockingQueue() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 7) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // To make sure cancellation task started before adding barrier task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels barrier task
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Task.sleep(nanoseconds: UInt64(5E9))
                }
            }
        }
    }

    func testCancellationOfMultipleBarrierTasksWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 8) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // To make sure cancellation task started before adding barrier task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels barrier tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Task.sleep(nanoseconds: UInt64(5E9))
                }
            }
        }
    }

    func
        testCancellationOfMultipleBarrierTasksAndOneConcurrentTaskWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 8) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // To make sure cancellation task started before adding barrier task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels barrier tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Task.sleep(nanoseconds: UInt64(5E9))
                }
            }
        }
    }
}
