/// A safer mechanism to interface between synchronous and asynchronous code,
/// forgiving correctness violations.
///
/// Resuming from a standard continuation more than once is undefined behavior.
/// Never resuming leaves the task in a suspended state indefinitely,
/// and leaks any associated resources. Use `SafeContinuation` if you are accessing
/// the same continuations in concurrent code and continuations have chance to be resumed
/// multiple times.
///
/// `SafeContinuation` performs runtime checks for multiple resume operations.
/// Only first resume operation is considered and rest are all ignored.
/// While there is no checks for missing resume operations,
/// `CheckedContinuation` can be used as underlying continuation value for additional runtime checks.
public final class SafeContinuation<C: Continuable>: Continuable {
    /// Tracks the status of continuation resuming for ``SafeContinuation``.
    ///
    /// Depending upon ``SafeContinuation`` status the ``SafeContinuation/resume(with:)``
    /// invocation effect is determined. Only first resume operation is considered and rest are all ignored.
    @frozen
    public enum Status {
        /// Indicates continuation is waiting to be resumed.
        ///
        /// Resuming ``SafeContinuation`` with this status returns control immediately to the caller.
        /// The task continues executing when its executor schedules it.
        case waiting
        /// Indicates continuation is waiting to be resumed with provided value.
        ///
        /// Resuming ``SafeContinuation`` with this status has no effect.
        case willResume(Result<C.Success, C.Failure>)
        /// Indicates continuation is already resumed.
        ///
        /// Resuming ``SafeContinuation`` with this status has no effect.
        case resumed
    }

    /// The platform dependent lock used to synchronize continuation resuming.
    private let locker: Locker
    /// The current status for continuation resumption.
    private var status: Status
    /// The actual continuation value.
    private var value: C?

    /// Check if externally provided continuation status valid considering current status.
    ///
    /// - Parameter status: The provided status that current status should be updated to.
    /// - Returns: Whether the current status can be updated to provided status.
    private func validateStatus(_ status: Status) -> Bool {
        switch (self.status, status) {
        case (.willResume, .waiting), (.willResume, .willResume): return false
        case (.resumed, .waiting), (.resumed, .willResume): return false
        default: return true
        }
    }

    /// Checks whether continuation is already resumed
    /// or to be resumed with provided value.
    public var resumed: Bool {
        return locker.perform {
            switch status {
            case .waiting:
                return false
            default:
                break
            }
            return true
        }
    }

    /// Creates a safe continuation from provided continuation.
    ///
    /// - Parameters:
    ///   - status: The initial ``Status`` of provided continuation.
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///   - locker: The platform lock to use to synchronize continuation state.
    ///             New lock object is created in case none provided.
    ///
    /// - Returns: The newly created safe continuation.
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    public init(
        status: Status = .waiting,
        with value: C? = nil,
        synchronizedWith locker: Locker = .init()
    ) {
        self.value = value
        self.locker = locker
        switch status {
        case .willResume(let result) where value != nil:
            value!.resume(with: result)
            self.status = .resumed
        default:
            self.status = status
        }
    }

    /// Store the provided continuation if no continuation was provided during initialization.
    ///
    /// Use this method to pass continuation if continuation can't be provided during initialization.
    /// If continuation provided already during initialization, invoking this method will cause runtime exception.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to store. After passing the continuation
    ///                   with this method, don’t use it outside of this object.
    ///   - status: The status to which current status should be updated.
    ///             Pass the ``Status`` of provided continuation.
    ///   - file: The file name to pass to the precondition.
    ///           The default is the file where method is called.
    ///   - line: The line number to pass to the precondition.
    ///           The default is the line where method is called.
    ///
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    public func add(
        continuation: C,
        status: Status = .waiting,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        locker.perform {
            precondition(
                value == nil,
                "Continuation can be provided only once",
                file: file, line: line
            )
            value = continuation
            let isValidStatus = validateStatus(status)
            switch isValidStatus ? status : self.status {
            case .willResume(let result):
                continuation.resume(with: result)
                self.status = .resumed
            case _ where isValidStatus:
                self.status = status
            default:
                break
            }
        }
    }

    /// Resume the task awaiting the continuation by having it return normally from its suspension point.
    ///
    /// A continuation must be resumed at least once. If the continuation has already resumed,
    /// then calling this method has no effect.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    ///
    /// - Parameter value: The value to return from the continuation.
    public func resume(returning value: C.Success) {
        self.resume(with: .success(value))
    }

    /// Resume the task that’s awaiting the continuation by returning.
    ///
    /// A continuation must be resumed at least once. If the continuation has already resumed,
    /// then calling this method has no effect.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    public func resume() where C.Success == Void {
        self.resume(returning: ())
    }

    /// Resume the task awaiting the continuation by having it throw an error from its suspension point.
    ///
    /// A continuation must be resumed at least once. If the continuation has already resumed,
    /// then calling this method has no effect.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    ///
    /// - Parameter error: The error to throw from the continuation.
    public func resume(throwing error: C.Failure) {
        self.resume(with: .failure(error))
    }

    /// Resume the task awaiting the continuation by having it either return normally
    /// or throw an error based on the state of the given `Result` value.
    ///
    /// A continuation must be resumed at least once. If the continuation has already resumed,
    /// then calling this method has no effect.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    ///
    /// - Parameter result: A value to either return or throw from the continuation.
    public func resume(with result: Result<C.Success, C.Failure>) {
        locker.perform {
            let finalResult: Result<C.Success, C.Failure>
            switch (status, value) {
            case (.waiting, .some):
                finalResult = result
            case (.willResume(let result), .some):
                finalResult = result
            case (.waiting, .none):
                status = .willResume(result)
                return
            default:
                return
            }
            value!.resume(with: finalResult)
            status = .resumed
        }
    }
}

extension SafeContinuation: ThrowingContinuable where C: ThrowingContinuable {
    /// Suspends the current task, then calls the given operation with a``SafeContinuation``
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
    ///   - operation: A closure that takes an ``SafeContinuation`` parameter.
    ///                You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the operation.
    /// - Throws: If cancelled or `resume(throwing:)` is called on the continuation,
    ///           this function throws that error.
    public static func withCancellation(
        synchronizedWith locker: Locker = .init(),
        function: String = #function,
        handler: @escaping @Sendable () -> Void,
        operation: @escaping (SafeContinuation<C>) -> Void
    ) async throws -> C.Success where C.Success: Sendable {
        let safeContinuation = SafeContinuation(synchronizedWith: locker)
        return try await withTaskCancellationHandler {
            return try await C.with(function: function) { continuation in
                safeContinuation.add(continuation: continuation)
                operation(safeContinuation)
            }
        } onCancel: { [weak safeContinuation] in
            safeContinuation?.cancel()
            handler()
        }
    }

    /// Suspends the current task, then calls the given closure with a ``SafeContinuation`` for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// ``SafeContinuation`` allows accessing and resuming the same continuations in concurrent code
    /// by keeping track of underlying continuation value state.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes a ``SafeContinuation`` parameter.
    ///         You must resume the continuation at least once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    public static func with(
        function: String = #function,
        _ body: (SafeContinuation<C>) -> Void
    ) async throws -> C.Success {
        return try await C.with(function: function) { continuation in
            body(SafeContinuation(with: continuation))
        }
    }
}

extension SafeContinuation: NonThrowingContinuable
where C: NonThrowingContinuable {
    /// Suspends the current task, then calls the given closure with a ``SafeContinuation`` for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// ``SafeContinuation`` allows accessing and resuming the same continuations in concurrent code
    /// by keeping track of underlying continuation value state.
    ///
    /// - Parameters:
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - fn: A closure that takes a ``SafeContinuation`` parameter.
    ///         You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    public static func with(
        function: String = #function,
        _ body: (SafeContinuation<C>) -> Void
    ) async -> C.Success {
        return await C.with(function: function) { continuation in
            body(SafeContinuation(with: continuation))
        }
    }
}

extension SafeContinuation: @unchecked Sendable where C.Success: Sendable {}
extension SafeContinuation.Status: Sendable where C.Success: Sendable {}
