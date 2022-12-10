/// A mechanism to interface between synchronous and asynchronous code,
/// with tracking state data.
///
/// Resuming from a standard continuation more than once is undefined behavior.
/// Never resuming leaves the task in a suspended state indefinitely,
/// and leaks any associated resources. Use `TrackedContinuation`
/// if you want to check whether continuation can be resumed.
///
/// `TrackedContinuation` stores continuation state,
/// and allows continuation value to be provided at a later state,
/// where it can be resumed with available result.
///
/// While there is no checks for missing resume operations,
/// `CheckedContinuation` can be used as underlying
/// continuation value for additional runtime checks.
///
/// - Important: The continuation stored mustn't be
///              resumed or used outside of this object.
@usableFromInline
internal final class TrackedContinuation<C: Continuable>: TrackableContinuable {
    /// Tracks the status of continuation resuming for ``TrackedContinuation``.
    ///
    /// Depending upon ``TrackedContinuation`` status the ``TrackedContinuation/resume(with:)``
    /// invocation effect is determined.
    enum Status {
        /// Indicates continuation is waiting to be resumed.
        ///
        /// Resuming ``TrackedContinuation`` with this status returns control immediately to the caller.
        /// The task continues executing when its executor schedules it.
        case waiting
        /// Indicates continuation is waiting to be resumed with provided value.
        ///
        /// This happens when ``TrackedContinuation/resume(with:)``
        /// invoked without binding ``TrackedContinuation`` with a base continuation
        ///
        /// Resuming ``TrackedContinuation`` with this status will trap.
        case willResume(Result<C.Success, C.Failure>)
        /// Indicates continuation is already resumed.
        ///
        /// Resuming ``TrackedContinuation`` with this status will trap.
        case resumed
    }

    /// The current status for continuation resumption.
    private var status: Status = .waiting
    /// The actual continuation for which state is tracked.
    private var value: C?

    /// Checks whether continuation is already resumed
    /// or to be resumed with provided value.
    @usableFromInline
    var resumed: Bool {
        switch status {
        case .waiting:
            return false
        default:
            break
        }
        return true
    }

    /// Tracks the provided continuation state.
    ///
    /// The provided  platform lock is used to synchronize
    /// continuation state.
    ///
    /// - Parameters:
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///
    /// - Returns: The newly created tracked continuation.
    /// - Important: The continuation passed mustn't be resumed before.
    ///              After passing the continuation with this method,
    ///              don’t use it outside of this object.
    @usableFromInline
    init(with value: C? = nil) {
        self.value = value
    }

    /// Store the provided continuation if no continuation was provided during initialization.
    ///
    /// Use this method to pass continuation if continuation can't be provided during initialization.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to store. After passing the continuation
    ///                   with this method, don’t use it outside of this object.
    ///
    /// - Important: The continuation passed mustn't be resumed before.
    ///              After passing the continuation with this method,
    ///              don’t use it outside of this object.
    ///
    /// - Important: If continuation provided already during initialization,
    ///              invoking this method will cause runtime exception.
    @usableFromInline
    func add(continuation: C) {
        precondition(
            value == nil,
            "Continuation can be provided only once"
        )
        value = continuation
        switch self.status {
        case .willResume(let result):
            continuation.resume(with: result)
            self.status = .resumed
        case .resumed:
            fatalError("Invalid move to resumed state")
        default:
            break
        }
    }

    /// Resume the task awaiting the continuation by having it either return normally
    /// or throw an error based on the state of the given `Result` value.
    ///
    /// A continuation must be resumed at least once. If the continuation has already resumed,
    /// then the attempt to resume the continuation will trap.
    ///
    /// After calling this method, control immediately returns to the caller.
    /// The task continues executing when its executor schedules it.
    ///
    /// - Parameter result: A value to either return or throw from the continuation.
    @usableFromInline
    func resume(with result: Result<C.Success, C.Failure>) {
        switch (status, value) {
        case (_, .some(let value)):
            value.resume(with: result)
            status = .resumed
        case (.waiting, .none):
            status = .willResume(result)
        default:
            fatalError("Multiple resume invoked")
        }
    }
}

//extension TrackedContinuation: @unchecked Sendable where C.Success: Sendable {}
extension TrackedContinuation.Status: Sendable where C.Success: Sendable {}
