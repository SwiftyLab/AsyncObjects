/// A type that allows to interface between synchronous and asynchronous code,
/// by representing synchronized task state and allowing exclusive task resuming
/// with some value or error.
///
/// Use synchronized continuations for interfacing Swift tasks with event loops,
/// delegate methods, callbacks, and other non-async scheduling mechanisms
/// where continuations have chance to be resumed multiple times.
@rethrows
@usableFromInline
internal protocol SynchronizedContinuable: Continuable {
    /// The  MUTual EXclusion object type used
    /// to synchronize continuation state.
    associatedtype Lock: Exclusible
    /// The actual continuation value type.
    associatedtype Value: Continuable
    where Value.Success == Success, Value.Failure == Failure

    /// Creates a synchronized continuation from provided continuation.
    ///
    /// The provided  MUTual EXclusion object is used to synchronize
    /// continuation state.
    ///
    /// - Parameters:
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///   - locker: The  MUTual EXclusion object to use to synchronize continuation state.
    ///
    /// - Returns: The newly created synchronized continuation.
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    init(with value: Value?, synchronizedWith locker: Lock)
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

extension SynchronizedContinuable
where Self: Sendable, Value: ThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `SynchronizedContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked after resuming continuation with
    /// `CancellationError` when the task is canceled. For example, even if the operation
    /// is running code that never checks for cancellation and provided continuation to operation hasn't been resumed,
    /// a cancellation handler still runs cancelling the continuation and provides a chance to run some cleanup code.
    ///
    /// - Parameters:
    ///   - locker: The platform lock to use to synchronize continuation state.
    ///             New lock object is created in case none provided.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `SynchronizedContinuable` parameter.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    static func withCancellation(
        synchronizedWith locker: Lock = .init(),
        function: String = #function,
        handler: @escaping @Sendable () -> Void,
        operation: @escaping (Self) -> Void
    ) async rethrows -> Success {
        let cancellable = Self.init(with: nil, synchronizedWith: locker)
        return try await withTaskCancellationHandler {
            return try await Value.with(
                function: function
            ) { continuation in
                cancellable.add(continuation: continuation)
                operation(cancellable)
            }
        } onCancel: {
            cancellable.cancel()
            handler()
        }
    }

    /// Suspends the current task, then calls the given closure with a `SynchronizedContinuable` for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `SynchronizedContinuable` allows accessing and resuming the same continuations in concurrent code
    /// by keeping track of underlying continuation value state.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - body: A closure that takes a `SynchronizedContinuable` parameter.
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
            body(Self(with: continuation, synchronizedWith: .init()))
        }
    }
}

extension SynchronizedContinuable
where Self: Sendable, Value: NonThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `SynchronizedContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked after resuming continuation with
    /// `CancellationError` when the task is canceled. For example, even if the operation
    /// is running code that never checks for cancellation and provided continuation to operation hasn't been resumed,
    /// a cancellation handler still runs cancelling the continuation and provides a chance to run some cleanup code.
    ///
    /// - Parameters:
    ///   - locker: The platform lock to use to synchronize continuation state.
    ///             New lock object is created in case none provided.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `SynchronizedContinuable` parameter.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    internal static func withCancellation(
        synchronizedWith locker: Lock = .init(),
        function: String = #function,
        handler: @escaping @Sendable () -> Void,
        operation: @escaping (Self) -> Void
    ) async -> Success {
        let cancellable = Self.init(with: nil, synchronizedWith: locker)
        return await withTaskCancellationHandler {
            return await Value.with(
                function: function
            ) { continuation in
                cancellable.add(continuation: continuation)
                operation(cancellable)
            }
        } onCancel: {
            cancellable.cancel()
            handler()
        }
    }

    /// Suspends the current task, then calls the given closure with a `SynchronizedContinuable` for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `SynchronizedContinuable` allows accessing and resuming the same continuations in concurrent code
    /// by keeping track of underlying continuation value state.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - body: A closure that takes a `SynchronizedContinuable` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @usableFromInline
    internal static func with(
        function: String = #function,
        _ body: (Self) -> Void
    ) async -> Success {
        return await Value.with(function: function) { continuation in
            body(Self(with: continuation, synchronizedWith: .init()))
        }
    }
}
