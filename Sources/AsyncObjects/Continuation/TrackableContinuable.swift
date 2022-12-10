/// A type that allows to interface between synchronous and asynchronous code,
/// by binding to a base ``Continuable`` value and tracking its state.
///
/// Use `TrackableContinuable` for interfacing Swift tasks with event loops,
/// delegate methods, callbacks, and other non-async scheduling mechanisms
/// where continuations resumption status need to be checked.
@rethrows
@usableFromInline
internal protocol TrackableContinuable: Continuable {
    associatedtype Value: Continuable
    where Value.Success == Success, Value.Failure == Failure

    /// Creates a trackable continuation from provided continuation.
    ///
    /// The provided  continuation is bound and resumption state is tracked.
    ///
    /// - Parameters:
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///
    /// - Returns: The newly created trackable continuation.
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    init(with value: Value?)
    /// Store the provided continuation if no continuation was provided during initialization.
    ///
    /// Use this method to pass continuation if continuation can't be provided during initialization.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to store.
    ///                   After passing the continuation with this method,
    ///                   don’t use it outside of this object.
    ///
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    func add(continuation: Value)
}

extension TrackableContinuable
where Self: Sendable, Value: ThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `TrackableContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked with the created continuation when the task is canceled.
    /// For example, even if the operation is running code that never checks for cancellation, a cancellation handler
    /// still runs to allow cancellation of the continuation and to run some cleanup code.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `TrackableContinuable` parameter.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    static func withCancellation(
        function: String = #function,
        handler: @escaping @Sendable (Self) -> Void,
        operation: @escaping (Self) -> Void
    ) async rethrows -> Success {
        let cancellable = Self(with: nil)
        return try await withTaskCancellationHandler {
            return try await Value.with(
                function: function
            ) { continuation in
                cancellable.add(continuation: continuation)
                operation(cancellable)
            }
        } onCancel: {
            handler(cancellable)
        }
    }

    /// Suspends the current task, then calls the given closure with a `TrackableContinuable` for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `TrackableContinuable` allows accessing and resuming the same continuations in concurrent code
    /// by keeping track of underlying continuation value state.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - body: A closure that takes a `TrackableContinuable` parameter.
    ///           You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @usableFromInline
    static func with(
        function: String = #function,
        _ body: (Self) -> Void
    ) async rethrows -> Success {
        return try await Value.with(function: function) { continuation in
            body(Self(with: continuation))
        }
    }
}

extension TrackableContinuable
where Self: Sendable, Value: NonThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `TrackableContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked with the created continuation when the task is canceled.
    /// For example, even if the operation is running code that never checks for cancellation, a cancellation handler
    /// still runs to allow cancellation of the continuation and to run some cleanup code.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `TrackableContinuable` parameter.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    internal static func withCancellation(
        function: String = #function,
        handler: @escaping @Sendable (Self) -> Void,
        operation: @escaping (Self) -> Void
    ) async -> Success {
        let cancellable = Self(with: nil)
        return await withTaskCancellationHandler {
            return await Value.with(
                function: function
            ) { continuation in
                cancellable.add(continuation: continuation)
                operation(cancellable)
            }
        } onCancel: {
            handler(cancellable)
        }
    }

    /// Suspends the current task, then calls the given closure with a `TrackableContinuable` for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `TrackableContinuable` allows accessing and resuming the same continuations in concurrent code
    /// by keeping track of underlying continuation value state.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - body: A closure that takes a `TrackableContinuable` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @usableFromInline
    internal static func with(
        function: String = #function,
        _ body: (Self) -> Void
    ) async -> Success {
        return await Value.with(function: function) { continuation in
            body(Self(with: continuation))
        }
    }
}
