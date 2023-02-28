public extension CancellationSource {
    #if swift(>=5.7)
    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    init(
        linkedWith sources: [CancellationSource],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            await withTaskGroup(of: Void.self) { group in
                sources.forEach { source in
                    group.addTask {
                        await source.add(
                            work: self,
                            file: file, function: function, line: line
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    init(
        linkedWith sources: CancellationSource...,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(
            linkedWith: sources,
            file: file, function: function, line: line
        )
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
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
    /// - Returns: The newly created cancellation source.
    init(
        cancelAfterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            try await self.cancel(
                afterNanoseconds: nanoseconds,
                file: file, function: function, line: line
            )
        }
    }
    #else
    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(
        linkedWith sources: [CancellationSource],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            await withTaskGroup(of: Void.self) { group in
                sources.forEach { source in
                    group.addTask {
                        await source.add(
                            work: self,
                            file: file, function: function, line: line
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(
        linkedWith sources: CancellationSource...,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(
            linkedWith: sources,
            file: file, function: function, line: line
        )
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
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
    /// - Returns: The newly created cancellation source.
    public convenience init(
        cancelAfterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            try await self.cancel(
                afterNanoseconds: nanoseconds,
                file: file, function: function, line: line
            )
        }
    }
    #endif
}
