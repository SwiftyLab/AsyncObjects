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
    @_unsafeInheritExecutor
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
    @_unsafeInheritExecutor
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
