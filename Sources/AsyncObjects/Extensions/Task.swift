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
