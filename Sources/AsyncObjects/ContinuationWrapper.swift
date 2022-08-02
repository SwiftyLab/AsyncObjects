/// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
/// Continuation is cancelled with error if current task is cancelled and cancellation handler is immediately invoked.
///
/// This operation cooperatively checks for cancellation and reacting to it by cancelling the throwing continuation with an error
/// and the cancellation handler is always and immediately invoked after that.
/// For example, even if the operation is running code that never checks for cancellation,
/// a cancellation handler still runs and provides a chance to run some cleanup code.
///
/// - Parameters:
///   - handler: A closure that is called after cancelling continuation.
///              You must not resume the continuation in closure.
///   - fn: A closure that takes a throwing continuation parameter.
///         You must resume the continuation exactly once.
///
/// - Returns: The value passed to the continuation.
/// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
///
/// - Important: The continuation provided in cancellation handler is already resumed with cancellation error.
///              Trying to resume the continuation here will cause runtime error/unexpected behavior.
func withThrowingContinuationCancellationHandler<C: ThrowingContinuable>(
    handler: @Sendable (C) -> Void,
    _ fn: (C) -> Void
) async throws -> C.Success where C.Failure == Error {
    let wrapper = ContinuationWrapper<C>()
    let value = try await withTaskCancellationHandler {
        guard let continuation = wrapper.value else { return }
        wrapper.cancel(withError: CancellationError())
        handler(continuation)
    } operation: { () -> C.Success in
        let value = try await C.with { continuation in
            wrapper.value = continuation
            fn(continuation)
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

extension Continuable where Failure == Error {
    /// Cancel continuation by resuming with cancellation error.
    @inlinable
    func cancel() { self.resume(throwing: CancellationError()) }
}

extension UnsafeContinuation: Continuable {}
extension CheckedContinuation: Continuable {}

protocol ThrowingContinuable: Continuable {
    /// The type of error to resume the continuation with in case of failure.
    associatedtype Failure = Error
    /// Suspends the current task, then calls the given closure
    /// with a throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behavior depending on type implemeting.
    ///
    /// - Parameter fn: A closure that takes the throwing continuation parameter.
    ///                 You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    static func with(_ fn: (Self) -> Void) async throws -> Success
}

extension UnsafeContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameter fn: A closure that takes an `UnsafeContinuation` parameter.
    ///                 You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    static func with(_ fn: (UnsafeContinuation<T, E>) -> Void) async throws -> T
    {
        return try await withUnsafeThrowingContinuation(fn)
    }
}

extension CheckedContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with a checked throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameter fn: A closure that takes a `CheckedContinuation` parameter.
    ///                 You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    static func with(_ body: (CheckedContinuation<T, E>) -> Void) async throws
        -> T
    {
        return try await withCheckedThrowingContinuation(body)
    }
}

#if DEBUG || ASYNCOBJECTS_USE_CHECKEDCONTINUATION
/// The continuation type used in package in `DEBUG` mode
/// or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on.
typealias GlobalContinuation<T, E: Error> = CheckedContinuation<T, E>
#else
/// The continuation type used in package in `RELEASE` mode
///and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag.
typealias GlobalContinuation<T, E: Error> = UnsafeContinuation<T, E>
#endif
