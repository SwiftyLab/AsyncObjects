public extension TaskGroup {
    /// Adds a child task to the group and starts the task.
    ///
    /// This method adds child task to the group and returns only after the child task is started.
    ///
    /// - Parameters:
    ///   - priority: The priority of the operation task. Omit this parameter or
    ///               pass `nil` to set the child task’s priority to the priority of the group.
    ///   - operation: The operation to execute as part of the task group.
    @inlinable
    mutating func addTaskAndStart(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> ChildTaskResult
    ) async {
        typealias C = UnsafeContinuation<Void, Never>
        await withUnsafeContinuation { (continuation: C) in
            self.addTask {
                continuation.resume()
                return await operation()
            }
        }
    }
}

public extension ThrowingTaskGroup {
    /// Adds a child task to the group and starts the task.
    ///
    /// This method adds child task to the group and returns only after the child task is started.
    /// This method doesn’t throw an error, even if the child task does. Instead,
    /// the corresponding call to `ThrowingTaskGroup.next()` rethrows that error.
    ///
    /// - Parameters:
    ///   - priority: The priority of the operation task. Omit this parameter or
    ///               pass `nil` to set the child task’s priority to the priority of the group.
    ///   - operation: The operation to execute as part of the task group.
    @inlinable
    mutating func addTaskAndStart(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> ChildTaskResult
    ) async {
        typealias C = UnsafeContinuation<Void, Never>
        await withUnsafeContinuation { (continuation: C) in
            self.addTask {
                continuation.resume()
                return try await operation()
            }
        }
    }
}

public extension Task {
    /// Runs the given operation asynchronously as part of
    /// a new top-level cancellable task on behalf of the current actor.
    ///
    /// Use this function to perform asynchronous work as part of a top-level task
    /// while being able to automatically cancel top-level task when the current task is cancelled.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Pass `nil` to use
    ///               the priority from `Task.currentPriority`.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from  the given operation, after it completes.
    /// - Throws: Error from the given operation.
    @inlinable
    @discardableResult
    static func withCancellableTask(
        priority: TaskPriority?,
        operation: @Sendable @escaping () async throws -> Success
    ) async rethrows -> Success where Failure == Error {
        let task = Self.init(priority: priority, operation: operation)
        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// Runs the given operation asynchronously as part of
    /// a new top-level cancellable task.
    ///
    /// Use this function to perform asynchronous work as part of a top-level task
    /// while being able to automatically cancel top-level task when the current task is cancelled.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from  the given operation, after it completes.
    /// - Throws: Error from the given operation.
    @inlinable
    @discardableResult
    static func withCancellableDetachedTask(
        priority: TaskPriority?,
        operation: @Sendable @escaping () async throws -> Success
    ) async rethrows -> Success where Failure == Error {
        let task = Self.detached(priority: priority, operation: operation)
        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }
}
