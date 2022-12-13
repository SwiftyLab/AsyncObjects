#if swift(>=5.7)
/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task resuming with some value or error.
///
/// Use continuations for interfacing Swift tasks with event loops, delegate methods, callbacks,
/// and other non-async scheduling mechanisms.
@rethrows
public protocol Continuable<Success,Failure> {
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
@rethrows
internal protocol ThrowingContinuable<Success>: Continuable
where Failure == Error {
    /// Suspends the current task, then calls the given closure
    /// with a throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behaviors depending on type implementing.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes the throwing continuation parameter.
    ///           You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @_unsafeInheritExecutor
    static func with(
        file: String, function: String, line: UInt,
        _ body: (Self) -> Void
    ) async throws -> Success
}

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task to be always resumed with some value.
///
/// Use non-throwing continuation to interface synchronous code that never fails with asynchronous code.
@rethrows
internal protocol NonThrowingContinuable<Success>: Continuable
where Failure == Never {
    /// Suspends the current task, then calls the given closure
    /// with a non-throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behavior depending on type implementing.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes the non-throwing continuation parameter.
    ///           You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @_unsafeInheritExecutor
    static func with(
        file: String, function: String, line: UInt,
        _ body: (Self) -> Void
    ) async -> Success
}
#else
/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task resuming with some value or error.
///
/// Use continuations for interfacing Swift tasks with event loops, delegate methods, callbacks,
/// and other non-async scheduling mechanisms.
@rethrows
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
@rethrows
internal protocol ThrowingContinuable: Continuable where Failure == Error {
    /// Suspends the current task, then calls the given closure
    /// with a throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behaviors depending on type implementing.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes the throwing continuation parameter.
    ///           You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @_unsafeInheritExecutor
    static func with(
        file: String, function: String, line: UInt,
        _ body: (Self) -> Void
    ) async throws -> Success
}

/// A type that allows to interface between synchronous and asynchronous code,
/// by representing task state and allowing task to be always resumed with some value.
///
/// Use non-throwing continuation to interface synchronous code that never fails with asynchronous code.
@rethrows
internal protocol NonThrowingContinuable: Continuable where Failure == Never {
    /// Suspends the current task, then calls the given closure
    /// with a non-throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once,
    /// subsequent resumes have different behavior depending on type implementing.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes the non-throwing continuation parameter.
    ///           You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @_unsafeInheritExecutor
    static func with(
        file: String, function: String, line: UInt,
        _ body: (Self) -> Void
    ) async -> Success
}
#endif

public extension Continuable {
    /// Dummy cancellation method for continuations
    /// that don't support cancellation.
    @inlinable
    func cancel() { /* Do nothing */  }

    /// Resume the task awaiting the continuation by having it return normally from its suspension point.
    ///
    /// A continuation must be resumed at least once.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    ///
    /// - Parameter value: The value to return from the continuation.
    @inlinable
    func resume(returning value: Success) {
        self.resume(with: .success(value))
    }

    /// Resume the task that’s awaiting the continuation by returning.
    ///
    /// A continuation must be resumed at least once.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    @inlinable
    func resume() where Success == Void {
        self.resume(with: .success(()))
    }

    /// Resume the task awaiting the continuation by having it throw an error from its suspension point.
    ///
    /// A continuation must be resumed at least once.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    ///
    /// - Parameter error: The error to throw from the continuation.
    @inlinable
    func resume(throwing error: Failure) {
        self.resume(with: .failure(error))
    }
}

public extension Continuable where Failure == Error {
    /// Cancel continuation by resuming with cancellation error.
    @inlinable
    func cancel() { self.resume(throwing: CancellationError()) }
}
