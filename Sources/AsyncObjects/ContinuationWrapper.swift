/// Suspends the current task, then calls the given closure with an unsafe throwing continuation for the current task.
/// Continuation is cancelled with error if current task is cancelled and cancellation handler is immediately invoked.
///
/// This operation cooperatively checks for cancellation and reacting to it by cancelling the unsafe throwing continuation with an error
/// and the cancellation handler is always and immediately invoked after that.
/// For example, even if the operation is running code that never checks for cancellation,
/// a cancellation handler still runs and provides a chance to run some cleanup code.
///
/// - Parameters:
///   - handler: A closure that is called after cancelling continuation.
///              You must not resume the continuation in closure.
///   - fn: A closure that takes an `UnsafeContinuation` parameter.
///         You must resume the continuation exactly once.
/// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
/// - Returns: The value passed to the continuation.
/// - Important: The continuation provided in cancellation handler is already resumed with cancellation error.
///              Trying to resume the continuation here will cause runtime error/unexpected behavior.
func withUnsafeThrowingContinuationCancellationHandler<T: Sendable>(
    handler: @Sendable (UnsafeContinuation<T, Error>) -> Void,
    _ fn: (UnsafeContinuation<T, Error>) -> Void
) async throws -> T {
    typealias Continuation = UnsafeContinuation<T, Error>
    let wrapper = Continuation.Wrapper()
    let value = try await withTaskCancellationHandler {
        guard let continuation = wrapper.value else { return }
        wrapper.cancel(withError: CancellationError())
        handler(continuation)
    } operation: { () -> T in
        let value = try await withUnsafeThrowingContinuation {
            (c: Continuation) in
            wrapper.value = c
            fn(c)
        }
        return value
    }
    return value
}

extension UnsafeContinuation {
    /// Wrapper type used to store `continuation` and
    /// provide cancellation mechanism.
    class Wrapper {
        /// The underlying continuation referenced.
        var value: UnsafeContinuation?

        /// Creates a new instance with a continuation reference passed.
        /// By default no continuation is stored.
        ///
        /// - Parameter value: A continuation reference to store.
        /// - Returns: The newly created continuation wrapper.
        init(value: UnsafeContinuation? = nil) {
            self.value = value
        }

        /// Resume continuation with passed error,
        /// without checking if continuation already resumed.
        ///
        /// - Parameter error: Error passed to continuation.
        func cancel(withError error: E) {
            value?.resume(throwing: error)
        }
    }
}

extension UnsafeContinuation where E == Error {
    /// Cancel continuation by resuming with cancellation error.
    @inlinable
    func cancel() { self.resume(throwing: CancellationError()) }
}
