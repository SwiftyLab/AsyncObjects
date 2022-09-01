#if swift(>=5.7)
/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task resuming with some value or error.
///
/// Use continuations for interfacing Swift tasks with event loops, delegate methods, callbacks,
/// and other non-async scheduling mechanisms.
public protocol Continuable<Success, Failure> {
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

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing a cancellable task state and allowing task resuming with some value or error.
///
/// Use non-throwing continuation to interface synchronous code that might fail,
/// or implements task cancellation mechanism, with asynchronous code.
public protocol ThrowingContinuable<Success>: Continuable
where Failure == Error {
    /// Suspends the current task, then calls the given closure
    /// with a throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behaviors depending on type implementing.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes the throwing continuation parameter.
    ///         You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    static func with(
        function: String,
        _ fn: (Self) -> Void
    ) async throws -> Success
}

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task to be always resumed with some value.
///
/// Use non-throwing continuation to interface synchronous code that never fails with asynchronous code.
public protocol NonThrowingContinuable<Success>: Continuable
where Failure == Never {
    /// Suspends the current task, then calls the given closure
    /// with a non-throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behavior depending on type implementing.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes the non-throwing continuation parameter.
    ///         You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    static func with(
        function: String,
        _ fn: (Self) -> Void
    ) async -> Success
}
#else
/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task resuming with some value or error.
///
/// Use continuations for interfacing Swift tasks with event loops, delegate methods, callbacks,
/// and other non-async scheduling mechanisms.
public protocol Continuable {
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

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing a cancellable task state and allowing task resuming with some value or error.
///
/// Use non-throwing continuation to interface synchronous code that might fail,
/// or implements task cancellation mechanism, with asynchronous code.
public protocol ThrowingContinuable: Continuable where Failure == Error {
    /// Suspends the current task, then calls the given closure
    /// with a throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behaviors depending on type implementing.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes the throwing continuation parameter.
    ///         You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    static func with(
        function: String,
        _ fn: (Self) -> Void
    ) async throws -> Success
}

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task to be always resumed with some value.
///
/// Use non-throwing continuation to interface synchronous code that never fails with asynchronous code.
public protocol NonThrowingContinuable: Continuable where Failure == Never {
    /// Suspends the current task, then calls the given closure
    /// with a non-throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behavior depending on type implementing.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes the non-throwing continuation parameter.
    ///         You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    static func with(
        function: String,
        _ fn: (Self) -> Void
    ) async -> Success
}
#endif

public extension Continuable where Failure == Error {
    /// Cancel continuation by resuming with cancellation error.
    @inlinable
    func cancel() { self.resume(throwing: CancellationError()) }
}

#if DEBUG || ASYNCOBJECTS_USE_CHECKEDCONTINUATION
/// The continuation type used in ``AsyncObjects`` package.
///
/// In `DEBUG` mode or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on
/// `CheckedContinuation` is used.
///
/// In `RELEASE` mode and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION`
/// flag `UnsafeContinuation` is used.
public typealias GlobalContinuation<T, E: Error> = CheckedContinuation<T, E>

extension CheckedContinuation: Continuable {}

extension CheckedContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with a checked throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes a `CheckedContinuation` parameter.
    ///         You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    public static func with(
        function: String = #function,
        _ body: (CheckedContinuation<T, E>) -> Void
    ) async throws -> T {
        return try await withCheckedThrowingContinuation(
            function: function,
            body
        )
    }
}

extension CheckedContinuation: NonThrowingContinuable where E == Never {
    /// Suspends the current task, then calls the given closure
    /// with a checked non-throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes a `CheckedContinuation` parameter.
    ///         You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    public static func with(
        function: String = #function,
        _ body: (CheckedContinuation<T, E>) -> Void
    ) async -> T {
        return await withCheckedContinuation(function: function, body)
    }
}
#else
/// The continuation type used in ``AsyncObjects`` package.
///
/// In `DEBUG` mode or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on
/// `CheckedContinuation` is used.
///
/// In `RELEASE` mode and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION`
/// flag `UnsafeContinuation` is used.
public typealias GlobalContinuation<T, E: Error> = UnsafeContinuation<T, E>

extension UnsafeContinuation: Continuable {}

extension UnsafeContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes an `UnsafeContinuation` parameter.
    ///         You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    public static func with(
        function: String = #function,
        _ fn: (UnsafeContinuation<T, E>) -> Void
    ) async throws -> T {
        return try await withUnsafeThrowingContinuation(fn)
    }
}

extension UnsafeContinuation: NonThrowingContinuable where E == Never {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe non-throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes an `UnsafeContinuation` parameter.
    ///         You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    public static func with(
        function: String = #function,
        _ fn: (UnsafeContinuation<T, E>) -> Void
    ) async -> T {
        return await withUnsafeContinuation(fn)
    }
}
#endif
