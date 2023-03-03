import XCTest
import OrderedCollections
@testable import AsyncObjects

typealias QE = OrderedDictionary<UUID, TaskQueue.QueuedContinuation>.Element
typealias TaskOption = (
    queue: TaskPriority?, task: TaskPriority?, flags: TaskQueue.Flags
)

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
        let task = Task.detached {
            try await queue.exec(flags: .block) {
                try await Task.sleep(seconds: 10)
            }
        }
        try await waitUntil(queue, timeout: 3) { $0.blocked }
        queue.signal()
        let blocked = await queue.blocked
        XCTAssertTrue(blocked)
        task.cancel()
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
                group.addTask { try await TaskQueue().checkWait(for: option) }
            }
            try await group.waitForAll()
        }
    }

    func testTaskExecutionWithJustAddingTasks() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .barrier) { c.yield(1) }
                await queue.addTaskAndStart { c.yield(2) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testDeinit() async throws {
        let queue = TaskQueue()
        await queue.exec(flags: .barrier) { /* Do nothing */  }
        await queue.exec { /* Do nothing */  }
        self.addTeardownBlock { [weak queue] in
            try await waitUntil(queue, timeout: 5) { $0.assertReleased() }
        }
    }
}

@MainActor
class TaskQueueTimeoutTests: XCTestCase {

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
                    try await TaskQueue().checkWaitTimeout(for: option)
                }
            }
            try await group.waitForAll()
        }
    }

    #if swift(>=5.7)
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
                    try await TaskQueue().checkWaitTimeout(
                        for: option,
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
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .block) { c.yield(1) }
                await queue.addTaskAndStart(flags: .block) { c.yield(2) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testExecutionOfTaskBeforeOperation() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart {
                    c.yield(1)
                    try await Task.sleep(seconds: 10)
                }
                await queue.addTaskAndStart(flags: .block) { c.yield(2) }
                c.finish()
            }
        }
        try await queue.wait(forSeconds: 3)
        await stream.assertElements()
    }

    func testExecutionOfTaskAfterOperation() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .block) {
                    c.yield(1)
                    try await Task.sleep(seconds: 1)
                    c.yield(2)
                }
                await queue.addTaskAndStart { c.yield(3) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testCancellation() async throws {
        let queue = TaskQueue()
        await queue.addTaskAndStart(flags: .block) {
            try await Task.sleep(seconds: 10)
        }
        let task = Task.detached {
            await queue.exec(flags: .block) {}
            try await queue.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        }
        do {
            task.cancel()
            try await task.value
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testAlreadyCancelledTask() async throws {
        let queue = TaskQueue()
        await queue.addTaskAndStart(flags: .block) {
            try await Task.sleep(seconds: 10)
        }
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 10)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            await queue.exec(flags: .block) {}
            try await queue.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        }
        do {
            task.cancel()
            try await task.value
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { throw CancellationError() }
            group.addTask {
                try await queue.exec(flags: .block) {
                    try await Task.sleep(seconds: 10)
                }
            }
            try? await group.waitForAll()
            // Cancels block task
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
    }

    func testMultipleCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { throw CancellationError() }
            group.addTask {
                try await queue.exec(flags: .block) {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec(flags: .block) {
                    try await Task.sleep(seconds: 10)
                }
            }
            try? await group.waitForAll()
            // Cancels block task
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
    }

    func testMixedeCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { throw CancellationError() }
            group.addTask {
                try await queue.exec(flags: .block) {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec(flags: .block) {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec {
                    try await Task.sleep(seconds: 3)
                }
            }
            try? await group.waitForAll()
            // Cancels block task
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
    }
}

@MainActor
class TaskQueueBarrierOperationTests: XCTestCase {

    func testExecutionOfTwoOperations() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .barrier) { c.yield(1) }
                await queue.addTaskAndStart(flags: .barrier) { c.yield(2) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testExecutionOfTaskBeforeOperation() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart {
                    c.yield(1)
                    try await Task.sleep(seconds: 1)
                    c.yield(2)
                }
                await queue.addTaskAndStart(flags: .barrier) { c.yield(3) }
                c.finish()
            }
        }
        try await queue.wait(forSeconds: 3)
        await stream.assertElements()
    }

    func testExecutionOfTaskAfterOperation() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .barrier) {
                    c.yield(1)
                    try await Task.sleep(seconds: 1)
                    c.yield(2)
                }
                await queue.addTaskAndStart { c.yield(3) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testCancellation() async throws {
        let queue = TaskQueue()
        await queue.addTaskAndStart(flags: .barrier) {
            try await Task.sleep(seconds: 10)
        }
        let task = Task.detached {
            await queue.exec(flags: .block) {}
            try await queue.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        }
        do {
            task.cancel()
            try await task.value
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testAlreadyCancelledTask() async throws {
        let queue = TaskQueue()
        await queue.addTaskAndStart(flags: .barrier) {
            try await Task.sleep(seconds: 10)
        }
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 10)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            await queue.exec(flags: .barrier) {}
            try await queue.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        }
        do {
            task.cancel()
            try await task.value
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { throw CancellationError() }
            group.addTask {
                try await queue.exec(flags: .barrier) {
                    try await Task.sleep(seconds: 10)
                }
            }
            try? await group.waitForAll()
            // Cancels block task
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
    }

    func testMultipleCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { throw CancellationError() }
            group.addTask {
                try await queue.exec(flags: .barrier) {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec(flags: .barrier) {
                    try await Task.sleep(seconds: 10)
                }
            }
            try? await group.waitForAll()
            // Cancels block task
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
    }

    func testMixedCancellationWithoutBlocking() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { throw CancellationError() }
            group.addTask {
                try await queue.exec(flags: .barrier) {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec(flags: .barrier) {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec {
                    try await Task.sleep(seconds: 3)
                }
            }
            try? await group.waitForAll()
            // Cancels block task
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
    }
}

@MainActor
class TaskQueueMixedOperationTests: XCTestCase {

    func testExecutionOfBlockTaskBeforeBarrierOperation() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .block) {
                    c.yield(1)
                    try await Task.sleep(seconds: 1)
                    c.yield(2)
                }
                await queue.addTaskAndStart(flags: .barrier) { c.yield(3) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testExecutionOfBlockTaskAfterBarrierOperation() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart(flags: .barrier) {
                    c.yield(1)
                    try await Task.sleep(seconds: 1)
                    c.yield(2)
                }
                await queue.addTaskAndStart(flags: .block) { c.yield(3) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testLongRunningConcurrentTaskWithShortBlockTaskBeforeBarrierOperation()
        async throws
    {
        let queue = TaskQueue()
        // Concurrent + Block + Barrier
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart {
                    c.yield(1)
                    try await Task.sleep(seconds: 3)
                    c.yield(2)
                }
                await queue.addTaskAndStart(flags: .block) { c.yield(2) }
                await queue.addTaskAndStart(flags: .barrier) { c.yield(3) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testLongRunningConcurrentTaskWithShortBlockTaskAfterBarrierOperation()
        async throws
    {
        let queue = TaskQueue()
        // Concurrent + Barrier + Block
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await queue.addTaskAndStart {
                    c.yield(1)
                    try await Task.sleep(seconds: 1)
                    c.yield(2)
                }
                await queue.addTaskAndStart(flags: .barrier) {
                    c.yield(3)
                    try await Task.sleep(seconds: 1)
                    c.yield(4)
                }
                await queue.addTaskAndStart(flags: .block) { c.yield(5) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    /// Scenario described in:
    /// https://forums.swift.org/t/concurrency-suspending-an-actor-async-func-until-the-actor-meets-certain-conditions/56580
    func testBarrierTaskWithMultipleConcurrentTasks() async throws {
        let queue = TaskQueue()
        let stream = AsyncStream<Int> { c in
            Task.detached {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<3 {
                        group.addTask {
                            await queue.addTaskAndStart {
                                c.yield(1)
                                try await Task.sleep(seconds: 1)
                                c.yield(1)
                            }
                        }
                    }
                    await group.waitForAll()
                }
                await queue.addTaskAndStart(flags: .barrier) {
                    c.yield(2)
                    try await Task.sleep(seconds: 1)
                    c.yield(3)
                }
                await queue.addTaskAndStart { c.yield(4) }
                await queue.addTaskAndStart { c.yield(4) }
                await queue.addTaskAndStart { c.yield(4) }
                c.finish()
            }
        }
        await stream.assertElements()
        try await queue.wait(forSeconds: 3)
    }

    func testCancellableAndNonCancellableTasks() async throws {
        let queue = TaskQueue()
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await queue.exec {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                try await queue.exec {
                    try await Task.sleep(seconds: 10)
                }
            }
            group.addTask {
                await queue.exec {
                    do {
                        try await Task.sleep(seconds: 10)
                        XCTFail("Unexpected task progression")
                    } catch is CancellationError {
                        /* Do nothing */
                    } catch {
                        XCTFail("Unexpected error \(error)")
                    }
                }
            }
            group.cancelAll()
        }
    }

    func testCancellableAndNonCancellableTasksWithBarrier() async throws {
        let queue = TaskQueue()
        try await withThrowingTaskGroup(of: Void.self) { group in
            await withTaskGroup(of: Void.self) { g in
                for _ in 0..<3 {
                    g.addTask {
                        await queue.addTaskAndStart {
                            try await Task.sleep(seconds: 1)
                        }
                    }
                }
                await g.waitForAll()
            }
            group.addTask {
                try await queue.exec(flags: .barrier) {
                    try await Task.sleep(seconds: 10)
                }
            }
            try await waitUntil(queue, timeout: 5) {
                guard
                    let (_, (_, flags)) = $0.queue.reversed().first
                else { return $0.blocked }
                return flags.contains(.barrier)
            }
            group.addTask {
                try await queue.exec {
                    try await Task.sleep(seconds: 1)
                    XCTFail("Unexpected task progression")
                }
            }
            group.addTask {
                await queue.exec {
                    do {
                        try await Task.sleep(seconds: 1)
                        XCTFail("Unexpected task progression")
                    } catch is CancellationError {
                        /* Do nothing */
                    } catch {
                        XCTFail("Unexpected error \(error)")
                    }
                }
            }
            group.addTask {
                await queue.exec {
                    do {
                        try await Task.sleep(seconds: 1)
                        XCTFail("Unexpected task progression")
                    } catch is CancellationError {
                        /* Do nothing */
                    } catch {
                        XCTFail("Unexpected error \(error)")
                    }
                }
            }
            try await waitUntil(queue, timeout: 5) { $0.blocked }
            group.cancelAll()
        }
        try await queue.wait(forSeconds: 3)
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

fileprivate extension TaskQueue {
    func addTaskAndStart<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async -> T
    ) async {
        await GlobalContinuation<Void, Never>.with { continuation in
            self.addTask(priority: priority, flags: flags) { () -> T in
                continuation.resume()
                return await operation()
            }
        }
    }

    func addTaskAndStart<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async throws -> T
    ) async {
        await GlobalContinuation<Void, Never>.with { continuation in
            self.addTask(priority: priority, flags: flags) { () -> T in
                continuation.resume()
                return try await operation()
            }
        }
    }

    @MainActor
    func checkWait(
        for option: TaskOption,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            await addTaskAndStart(priority: option.task, flags: option.flags) {
                try await Task.sleep(seconds: 1)
            }
            group.addTask { try await self.wait(forSeconds: 3) }
            try await group.waitForAll()
        }
        try await self.wait(forSeconds: 3)
    }

    @MainActor
    func checkWaitTimeout(
        for option: TaskOption,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws {
        await addTaskAndStart(
            priority: option.task,
            flags: [option.flags, .block]
        ) {
            try await Task.sleep(seconds: 10)
        }
        do {
            try await self.wait(forSeconds: 5)
            XCTFail("Unexpected task progression", file: file, line: line)
        } catch is DurationTimeoutError {}
    }

    #if swift(>=5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    @MainActor
    func checkWaitTimeout<C: Clock>(
        for option: TaskOption,
        clock: C,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async throws where C.Duration == Duration {
        await addTaskAndStart(
            priority: option.task,
            flags: [option.flags, .block]
        ) {
            try await Task.sleep(seconds: 10)
        }
        do {
            try await self.wait(forSeconds: 5)
            XCTFail("Unexpected task progression", file: file, line: line)
        } catch is DurationTimeoutError {}
    }
    #endif
}

fileprivate extension AsyncSequence where Element: BinaryInteger {
    func assertElements(
        initial value: Element = .zero,
        diff: Element = 1,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) async rethrows {
        var value = value
        for try await val in self where value != val {
            XCTAssertEqual(val, value + diff, file: file, line: line)
            value = val
        }
    }
}
