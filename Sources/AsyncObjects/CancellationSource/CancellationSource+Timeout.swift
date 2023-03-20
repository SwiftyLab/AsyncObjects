public extension CancellationSource {
    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
    ///
    /// - Parameters:
    ///   - priority: The minimum priority of task that this source is going to handle.
    ///               By default, priority is `.background`.
    ///   - nanoseconds: The delay after which cancellation event triggered.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    ///
    /// - NOTE: `CancellationSource` uses `Task`'s `result` and `value` APIs
    ///         to wait for completion which has side effect of increasing `Task`'s priority.
    ///         Hence, provide the least priority for the submitted tasks to use in cancellation task.
    init(
        priority: TaskPriority = .background,
        cancelAfterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(priority: priority)
        self.cancel(
            afterNanoseconds: nanoseconds,
            file: file, function: function, line: line
        )
    }

    /// Trigger cancellation event after provided delay and waits until cancellation triggered.
    ///
    /// Initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - nanoseconds: The delay after which cancellation event triggered.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    func cancel(
        afterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
        self.cancel(file: file, function: function, line: line)
    }

    /// Trigger cancellation event after provided delay.
    ///
    /// Initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - nanoseconds: The delay after which cancellation event triggered.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    func cancel(
        afterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            try await self.cancel(
                afterNanoseconds: nanoseconds,
                file: file, function: function, line: line
            )
        }
    }
}

#if swift(>=5.7)
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
public extension CancellationSource {
    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object at specified deadline.
    ///
    /// - Parameters:
    ///   - priority: The minimum priority of task that this source is going to handle.
    ///               By default, priority is `.background`.
    ///   - deadline: The instant in the provided clock at which cancellation event triggered.
    ///   - clock: The clock for which cancellation deadline provided.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    ///
    /// - NOTE: `CancellationSource` uses `Task`'s `result` and `value` APIs
    ///         to wait for completion which has side effect of increasing `Task`'s priority.
    ///         Hence, provide the least priority for the submitted tasks to use in cancellation task.
    init<C: Clock>(
        priority: TaskPriority = .background,
        at deadline: C.Instant,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(priority: priority)
        self.cancel(
            at: deadline, clock: clock,
            file: file, function: function, line: line
        )
    }

    /// Trigger cancellation event at provided deadline and waits until cancellation triggered.
    ///
    /// Initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - deadline: The instant in the provided clock at which cancellation event triggered.
    ///   - clock: The clock for which cancellation deadline provided.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    func cancel<C: Clock>(
        at deadline: C.Instant,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        try await Task.sleep(until: deadline, clock: clock)
        self.cancel(file: file, function: function, line: line)
    }

    /// Trigger cancellation event at provided deadline.
    ///
    /// Initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - deadline: The instant in the provided clock at which cancellation event triggered.
    ///   - clock: The clock for which cancellation deadline provided.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    func cancel<C: Clock>(
        at deadline: C.Instant,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            try await self.cancel(
                at: deadline, clock: clock,
                file: file, function: function, line: line
            )
        }
    }
}
#endif
