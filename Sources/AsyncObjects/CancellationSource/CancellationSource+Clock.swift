#if swift(>=5.7)
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
public extension CancellationSource {
    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object at specified deadline.
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
    /// - Returns: The newly created cancellation source.
    init<C: Clock>(
        at deadline: C.Instant,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            try await self.cancel(
                at: deadline, clock: clock,
                file: file, function: function, line: line
            )
        }
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
        await cancelAll(file: file, function: function, line: line)
    }
}
#endif
