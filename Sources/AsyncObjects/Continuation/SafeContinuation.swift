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
@usableFromInline
internal final class SafeContinuation<C: Continuable>: SynchronizedContinuable {
    /// Tracks the status of continuation resuming for ``SafeContinuation``.
    ///
    /// Depending upon ``SafeContinuation`` status the ``SafeContinuation/resume(with:)``
    /// invocation effect is determined. Only first resume operation is considered and rest are all ignored.
    enum Status {
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
    @usableFromInline
    var resumed: Bool {
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
    /// The provided  platform lock is used to synchronize
    /// continuation state.
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
    init(
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

    /// Creates a safe continuation from provided continuation.
    ///
    /// The provided  platform lock is used to synchronize
    /// continuation state.
    ///
    /// - Parameters:
    ///   - value: The continuation value to store. After passing the continuation
    ///            with this method, don’t use it outside of this object.
    ///   - locker: The platform lock to use to synchronize continuation state.
    ///             New lock object is created in case none provided.
    ///
    /// - Returns: The newly created safe continuation.
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    @usableFromInline
    convenience init(with value: C?, synchronizedWith locker: Locker) {
        self.init(status: .waiting, with: value, synchronizedWith: locker)
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
    func add(
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

    /// Store the provided continuation if no continuation was provided during initialization.
    ///
    /// Use this method to pass continuation if continuation can't be provided during initialization.
    /// If continuation provided already during initialization, invoking this method will cause runtime exception.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to store. After passing the continuation
    ///                   with this method, don’t use it outside of this object.
    ///
    /// - Important: After passing the continuation with this method,
    ///              don’t use it outside of this object.
    @usableFromInline
    func add(continuation: C) {
        self.add(continuation: continuation, status: .waiting)
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
    @usableFromInline
    func resume(with result: Result<C.Success, C.Failure>) {
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

extension SafeContinuation: @unchecked Sendable where C.Success: Sendable {}
extension SafeContinuation.Status: Sendable where C.Success: Sendable {}
