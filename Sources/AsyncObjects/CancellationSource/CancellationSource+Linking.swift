public extension CancellationSource {
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
        sources.forEach { $0.register(task: self) }
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
}
