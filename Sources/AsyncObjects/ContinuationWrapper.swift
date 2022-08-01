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
///
/// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
/// - Returns: The value passed to the continuation.
///
/// - Important: The continuation provided in cancellation handler is already resumed with cancellation error.
///              Trying to resume the continuation here will cause runtime error/unexpected behavior.
func withUnsafeThrowingContinuationCancellationHandler<T: Sendable>(
    handler: @Sendable (UnsafeContinuation<T, Error>) -> Void,
    _ fn: (UnsafeContinuation<T, Error>) -> Void
) async throws -> T {
    typealias Continuation = UnsafeContinuation<T, Error>
    let wrapper = ContinuationWrapper<Continuation>()
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

/// Wrapper type used to store `continuation` and
/// provide cancellation mechanism.
final class ContinuationWrapper<Wrapped: Continuable> {
    /// The underlying continuation referenced.
    var value: Wrapped?

    /// Creates a new instance with a continuation reference passed.
    /// By default no continuation is stored.
    ///
    /// - Parameter value: A continuation reference to store.
    ///
    /// - Returns: The newly created continuation wrapper.
    init(value: Wrapped? = nil) {
        self.value = value
    }

    /// Resume continuation with passed error,
    /// without checking if continuation already resumed.
    ///
    /// - Parameter error: Error passed to continuation.
    func cancel(withError error: Wrapped.Failure) {
        value?.resume(throwing: error)
    }
}

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task resuming with some value or error.
protocol Continuable: Sendable {
    /// The type of value to resume the continuation with in case of success.
    associatedtype Success
    /// The type of error to resume the continuation with in case of failure.
    associatedtype Failure: Error
    /// Resume the task awaiting the continuation by having it return normally from its suspension point.
    ///
    /// - Parameter value: The value to return from the continuation.
    func resume(returning value: Success)
    /// Resume the task awaiting the continuation by having it throw an error from its suspension point.
    ///
    /// - Parameter error: The error to throw from the continuation.
    func resume(throwing error: Failure)
    /// Resume the task awaiting the continuation by having it either return normally
    /// or throw an error based on the state of the given `Result` value.
    ///
    /// - Parameter result: A value to either return or throw from the continuation.
    func resume(with result: Result<Success, Failure>)
}

extension UnsafeContinuation: Continuable {}

extension UnsafeContinuation where E == Error {
    /// Cancel continuation by resuming with cancellation error.
    @inlinable
    func cancel() { self.resume(throwing: CancellationError()) }
}
