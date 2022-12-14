#if swift(>=5.7)
/// A type that allows to interface between synchronous and asynchronous code,
/// by binding to a base ``Continuable`` value and tracking its state.
///
/// Use `TrackableContinuable` for interfacing Swift tasks with event loops,
/// delegate methods, callbacks, and other non-async scheduling mechanisms
/// where continuations resumption status need to be checked.
@rethrows
@usableFromInline
internal protocol TrackableContinuable: Continuable {
    associatedtype ID
    associatedtype Value: Continuable
    where Value.Success == Success, Value.Failure == Failure

    /// Creates a trackable continuation from provided continuation.
    ///
    /// The provided  continuation is bound and resumption state is tracked.
    /// - Parameters:
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///   - id: Optional id to associate new instance with.
    ///   - file: The file where track continuation requested.
    ///   - function: The function where track continuation requested.
    ///   - line: The line where track continuation requested.
    ///
    /// - Returns: The newly created trackable continuation.
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    init(
        with value: Value?, id: ID?,
        file: String, function: String, line: UInt
    )
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
where Self: Sendable, Value: Sendable & ThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `TrackableContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked with the created continuation when the task is canceled.
    /// For example, even if the operation is running code that never checks for cancellation, a cancellation handler
    /// still runs to allow cancellation of the continuation and to run some cleanup code.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `TrackableContinuable` parameter and
    ///                a pre-initialization handler that needs to run before managing continuation.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    @_unsafeInheritExecutor
    static func withCancellation(
        id: ID,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        handler: @Sendable (Self) -> Void,
        operation: (Self, @escaping @Sendable () -> Void) -> Void
    ) async rethrows -> Success {
        let cancellable = Self(
            with: nil, id: id,
            file: file, function: function, line: line
        )
        return try await withTaskCancellationHandler {
            return try await Value.with(
                file: file, function: function, line: line
            ) { continuation in
                operation(cancellable) {
                    cancellable.add(continuation: continuation)
                }
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
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `TrackableContinuable` parameter.
    ///           You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @usableFromInline
    @_unsafeInheritExecutor
    static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async rethrows -> Success {
        return try await Value.with(
            file: file, function: function, line: line
        ) { continuation in
            body(
                Self(
                    with: continuation, id: nil,
                    file: file, function: function, line: line
                )
            )
        }
    }
}

extension TrackableContinuable
where Self: Sendable, Value: Sendable & NonThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `TrackableContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked with the created continuation when the task is canceled.
    /// For example, even if the operation is running code that never checks for cancellation, a cancellation handler
    /// still runs to allow cancellation of the continuation and to run some cleanup code.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `TrackableContinuable` parameter and
    ///                a pre-initialization handler that needs to run before managing continuation.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    @_unsafeInheritExecutor
    internal static func withCancellation(
        id: ID,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        handler: @Sendable (Self) -> Void,
        operation: (Self, @escaping @Sendable () -> Void) -> Void
    ) async -> Success {
        let cancellable = Self(
            with: nil, id: id,
            file: file, function: function, line: line
        )
        return await withTaskCancellationHandler {
            return await Value.with(
                file: file, function: function, line: line
            ) { continuation in
                operation(cancellable) {
                    cancellable.add(continuation: continuation)
                }
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
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `TrackableContinuable` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @usableFromInline
    @_unsafeInheritExecutor
    internal static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async -> Success {
        return await Value.with(
            file: file, function: function, line: line
        ) { continuation in
            body(
                Self(
                    with: continuation, id: nil,
                    file: file, function: function, line: line
                )
            )
        }
    }
}
#else
/// A type that allows to interface between synchronous and asynchronous code,
/// by binding to a base ``Continuable`` value and tracking its state.
///
/// Use `TrackableContinuable` for interfacing Swift tasks with event loops,
/// delegate methods, callbacks, and other non-async scheduling mechanisms
/// where continuations resumption status need to be checked.
@rethrows
@usableFromInline
internal protocol TrackableContinuable: Continuable {
    associatedtype ID
    associatedtype Value: Continuable
    where Value.Success == Success, Value.Failure == Failure

    /// Creates a trackable continuation from provided continuation.
    ///
    /// The provided  continuation is bound and resumption state is tracked.
    /// - Parameters:
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///   - id: Optional id to associate new instance with.
    ///   - file: The file where track continuation requested.
    ///   - function: The function where track continuation requested.
    ///   - line: The line where track continuation requested.
    ///
    /// - Returns: The newly created trackable continuation.
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    init(
        with value: Value?, id: ID?,
        file: String, function: String, line: UInt
    )
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
where Self: Sendable, Value: Sendable & ThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `TrackableContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked with the created continuation when the task is canceled.
    /// For example, even if the operation is running code that never checks for cancellation, a cancellation handler
    /// still runs to allow cancellation of the continuation and to run some cleanup code.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `TrackableContinuable` parameter and
    ///                a pre-initialization handler that needs to run before managing continuation.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    static func withCancellation(
        id: ID,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        handler: @Sendable (Self) -> Void,
        operation: (Self, @escaping @Sendable () -> Void) -> Void
    ) async rethrows -> Success {
        let cancellable = Self(
            with: nil, id: id,
            file: file, function: function, line: line
        )
        return try await withTaskCancellationHandler {
            return try await Value.with(
                file: file, function: function, line: line
            ) { continuation in
                operation(cancellable) {
                    cancellable.add(continuation: continuation)
                }
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
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `TrackableContinuable` parameter.
    ///           You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @usableFromInline
    static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async rethrows -> Success {
        return try await Value.with(
            file: file, function: function, line: line
        ) { continuation in
            body(
                Self(
                    with: continuation, id: nil,
                    file: file, function: function, line: line
                )
            )
        }
    }
}

extension TrackableContinuable
where Self: Sendable, Value: Sendable & NonThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a `TrackableContinuable`
    /// for the current task with a cancellation handler that’s immediately invoked if the current task is canceled.
    ///
    /// This differs from the operation cooperatively checking for cancellation and reacting to it in that
    /// the cancellation handler is always and immediately invoked with the created continuation when the task is canceled.
    /// For example, even if the operation is running code that never checks for cancellation, a cancellation handler
    /// still runs to allow cancellation of the continuation and to run some cleanup code.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - handler: A handler immediately invoked if task is cancelled.
    ///   - operation: A closure that takes an `TrackableContinuable` parameter and
    ///                a pre-initialization handler that needs to run before managing continuation.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    @usableFromInline
    internal static func withCancellation(
        id: ID,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        handler: @Sendable (Self) -> Void,
        operation: (Self, @escaping @Sendable () -> Void) -> Void
    ) async -> Success {
        let cancellable = Self(
            with: nil, id: id,
            file: file, function: function, line: line
        )
        return await withTaskCancellationHandler {
            return await Value.with(
                file: file, function: function, line: line
            ) { continuation in
                operation(cancellable) {
                    cancellable.add(continuation: continuation)
                }
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
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `TrackableContinuable` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @usableFromInline
    internal static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async -> Success {
        return await Value.with(
            file: file, function: function, line: line
        ) { continuation in
            body(
                Self(
                    with: continuation, id: nil,
                    file: file, function: function, line: line
                )
            )
        }
    }
}
#endif
