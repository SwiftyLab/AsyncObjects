@rethrows
public protocol Cancellable: Sendable {
    @Sendable
    func cancel(file: String, function: String, line: UInt)
    @Sendable
    func wait(file: String, function: String, line: UInt) async throws
}

extension Task: Cancellable {
    @inlinable
    @Sendable
    @_disfavoredOverload
    public func cancel(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.cancel()
    }

    @inlinable
    @Sendable
    public func wait(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        let _ = try await self.value
    }
}
