public extension CancellationSource {
    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - priority: The minimum priority of task that this source is going to handle.
    ///               By default, minimum priority of provided `sources` is used or
    ///               `.background` if no provided `sources`.
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    ///
    /// - NOTE: `CancellationSource` uses `Task`'s `result` and `value` APIs
    ///         to wait for completion which has side effect of increasing `Task`'s priority.
    ///         Hence, provide the least priority for the submitted tasks to use in cancellation task.
    init(
        priority: TaskPriority? = nil,
        linkedWith sources: [CancellationSource],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let priority = priority ?? sources.map(\.priority).min() ?? .background
        self.init(priority: priority)
        sources.forEach {
            $0.register(task: self, file: file, function: function, line: line)
        }
    }

    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - priority: The minimum priority of task that this source is going to handle.
    ///               By default, minimum priority of provided `sources` is used or
    ///               `.background` if no provided `sources`.
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    ///
    /// - NOTE: `CancellationSource` uses `Task`'s `result` and `value` APIs
    ///         to wait for completion which has side effect of increasing `Task`'s priority.
    ///         Hence, provide the least priority for the submitted tasks to use in cancellation task.
    init(
        priority: TaskPriority? = nil,
        linkedWith sources: CancellationSource...,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(
            priority: priority, linkedWith: sources,
            file: file, function: function, line: line
        )
    }
}
