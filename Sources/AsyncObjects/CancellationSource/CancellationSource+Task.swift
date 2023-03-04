public extension Task {
    /// Runs the given non-throwing operation asynchronously as part of a new top-level task on behalf of the current actor,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    init(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async -> Success
    ) where Failure == Never {
        self.init(priority: priority, operation: operation)
        cancellationSource.register(
            task: self,
            file: file,
            function: function,
            line: line
        )
    }

    /// Runs the given throwing operation asynchronously as part of a new top-level task on behalf of the current actor,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    init(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async throws -> Success
    ) where Failure == Error {
        self.init(priority: priority, operation: operation)
        cancellationSource.register(
            task: self,
            file: file,
            function: function,
            line: line
        )
    }

    /// Runs the given non-throwing operation asynchronously as part of a new top-level task,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    static func detached(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async -> Success
    ) -> Self where Failure == Never {
        let task = Task.detached(priority: priority, operation: operation)
        cancellationSource.register(
            task: task,
            file: file,
            function: function,
            line: line
        )
        return task
    }

    /// Runs the given throwing operation asynchronously as part of a new top-level task,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    static func detached(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async throws -> Success
    ) -> Self where Failure == Error {
        let task = Task.detached(priority: priority, operation: operation)
        cancellationSource.register(
            task: task,
            file: file,
            function: function,
            line: line
        )
        return task
    }
}
