import Foundation
import Dispatch

/// An object that bridges asynchronous work under structured concurrency
/// to Grand Central Dispatch (GCD or `libdispatch`) as `Operation`.
///
/// Using this object traditional `libdispatch` APIs can be used along with structured concurrency
/// making concurrent task management flexible in terms of managing dependencies.
///
/// You can start the operation by adding it to an `OperationQueue`,
/// or by manually calling the ``signal(file:function:line:)`` or ``start()`` method.
/// Wait for operation completion asynchronously by calling ``wait(file:function:line:)`` method
/// or its timeout variation ``wait(until:tolerance:clock:file:function:line:)``:
///
/// ```swift
/// // create operation with async action
/// let operation = TaskOperation {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
/// // start operation to execute action
/// operation.start() // operation.signal()
///
/// // wait for operation completion asynchronously,
/// // fails only if task cancelled
/// try await operation.wait()
/// // or wait with some timeout
/// try await operation.wait(forNanoseconds: 1_000_000_000)
/// // or wait synchronously for completion
/// operation.waitUntilFinished()
/// ```
public final class TaskOperation<R: Sendable>: Operation, AsyncObject,
    ContinuableCollection, Loggable, @unchecked Sendable
{
    /// The asynchronous action to perform as part of the operation..
    private let underlyingAction: @Sendable () async throws -> R
    /// The top-level task that executes asynchronous action provided
    /// on behalf of the actor where operation started.
    private var execTask: Task<R, Error>?
    /// The platform dependent lock used to
    /// synchronize data access and modifications.
    @usableFromInline
    internal let locker: Locker

    /// A type representing a set of behaviors for the executed
    /// task type and task completion behavior.
    ///
    /// ``TaskOperation`` determines the execution behavior of
    /// provided action as task based on the provided flags.
    public typealias Flags = TaskOperationFlags
    /// The priority of top-level task executed.
    ///
    /// In case of `nil` priority from `Task.currentPriority`
    /// of task that starts the operation used.
    public let priority: TaskPriority?
    /// A set of behaviors for the executed task type and task completion behavior.
    ///
    /// Provided flags determine the execution behavior of
    /// the action as task.
    public let flags: Flags

    /// A Boolean value indicating whether the operation executes its task asynchronously.
    ///
    /// Always returns true, since the operation always executes its task asynchronously.
    public override var isAsynchronous: Bool { true }

    /// Private store for boolean value indicating whether the operation is currently cancelled.
    @usableFromInline
    internal var _isCancelled: Bool = false
    /// A Boolean value indicating whether the operation has been cancelled.
    ///
    /// Returns whether the underlying top-level task is cancelled or not.
    /// The default value of this property is `false`.
    /// Calling the ``cancel()`` method of this object sets the value of this property to `true`.
    public override internal(set) var isCancelled: Bool {
        get { locker.perform { execTask?.isCancelled ?? _isCancelled } }
        @usableFromInline
        set {
            willChangeValue(forKey: "isCancelled")
            locker.perform {
                _isCancelled = newValue
                guard newValue else { return }
                execTask?.cancel()
            }
            didChangeValue(forKey: "isCancelled")
        }
    }

    /// Private store for boolean value indicating whether the operation is currently executing.
    @usableFromInline
    internal var _isExecuting: Bool = false
    /// A Boolean value indicating whether the operation is currently executing.
    ///
    /// The value of this property is true if the operation is currently executing
    /// provided asynchronous operation or false if it is not.
    public override internal(set) var isExecuting: Bool {
        get { locker.perform { _isExecuting } }
        @usableFromInline
        set {
            willChangeValue(forKey: "isExecuting")
            locker.perform { _isExecuting = newValue }
            didChangeValue(forKey: "isExecuting")
        }
    }

    /// Private store for boolean value indicating whether the operation has finished executing its task.
    @usableFromInline
    internal var _isFinished: Bool = false
    /// A Boolean value indicating whether the operation has finished executing its task.
    ///
    /// The value of this property is true if the operation is finished executing or cancelled
    /// provided asynchronous operation or false if it is not.
    public override internal(set) var isFinished: Bool {
        get { locker.perform { _isFinished } }
        @usableFromInline
        set {
            willChangeValue(forKey: "isFinished")
            locker.perform {
                _isFinished = newValue
                guard newValue, !continuations.isEmpty else { return }
                continuations.forEach { $0.value.resume() }
                continuations = [:]
            }
            didChangeValue(forKey: "isFinished")
        }
    }

    /// The result of provided asynchronous operation execution.
    ///
    /// Will be success if provided operation completed successfully,
    /// or failure returned with error.
    public var result: Result<R, Error> {
        get async {
            (await execTask?.result)
                ?? (isCancelled
                    ? .failure(CancellationError())
                    : .failure(EarlyInvokeError()))
        }
    }

    /// Creates a new operation that executes the provided asynchronous task.
    ///
    /// The operation execution only starts after ``start()`` is invoked.
    /// Operation completes when underlying asynchronous task finishes.
    /// The provided lock is used to synchronize operation property access and modifications
    /// to prevent data races.
    ///
    /// - Parameters:
    ///   - shouldTrackUnstructuredTasks: Whether to wait for all the unstructured tasks created
    ///                                   as part of provided asynchronous action.
    ///   - locker: The locker to use to synchronize property read and mutations.
    ///             New lock object is created in case none provided.
    ///   - priority: The priority of the task that operation executes.
    ///               Pass `nil` to use the priority from `Task.currentPriority`
    ///               of task that starts the operation.
    ///   - operation: The asynchronous operation to execute.
    ///
    /// - Returns: The newly created asynchronous operation.
    public init(
        synchronizedWith locker: Locker = .init(),
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @escaping @Sendable () async throws -> R
    ) {
        self.locker = locker
        self.priority = priority
        self.flags = flags
        self.underlyingAction = operation
        super.init()
    }

    deinit {
        execTask?.cancel()
        locker.perform { self.continuations.forEach { $0.value.cancel() } }
    }

    /// Begins the execution of the operation.
    ///
    /// Updates the execution state of the operation and
    /// runs the given operation asynchronously
    /// as part of a new top-level task on behalf of the current actor.
    public override func start() {
        guard !self.isFinished else { return }
        isFinished = false
        isExecuting = true
        main()
    }

    /// Performs the provided asynchronous task.
    ///
    /// Runs the given operation asynchronously
    /// as part of a new top-level task on behalf of the current actor.
    public override func main() {
        guard isExecuting, execTask == nil else { return }
        let final = { @Sendable[weak self] in self?.finish(); return }
        execTask = flags.createTask(
            priority: priority,
            operation: underlyingAction,
            onComplete: final
        )
    }

    /// Advises the operation object that it should stop executing its task.
    ///
    /// Initiates cooperative cancellation for provided asynchronous operation
    /// and moves to finished state.
    ///
    /// Calling this method on a task that doesn’t support cancellation has no effect.
    /// Likewise, if the task has already run past the last point where it would stop early,
    /// calling this method has no effect.
    public override func cancel() {
        isCancelled = true
        finish()
    }

    /// Moves this operation to finished state.
    ///
    /// Must be called either when operation completes or cancelled.
    @inlinable
    internal func finish() {
        isExecuting = false
        isFinished = true
    }

    // MARK: AsyncObject
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = TrackedContinuation<
        GlobalContinuation<Void, Error>
    >
    /// The continuations stored with an associated key for all the suspended task that are waiting for operation completion.
    @usableFromInline
    internal private(set) var continuations: [UUID: Continuation] = [:]

    /// Add continuation with the provided key in `continuations` map.
    ///
    /// - Parameters:
    ///   - continuation: The `continuation` to add.
    ///   - key: The key in the map.
    ///   - file: The file add request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function add request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line add request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func addContinuation(
        _ continuation: Continuation,
        withKey key: UUID,
        file: String, function: String, line: UInt
    ) {
        locker.perform {
            guard !continuation.resumed else {
                log(
                    "Already resumed, not tracking", id: key,
                    file: file, function: function, line: line
                )
                return
            }

            guard !isFinished else {
                continuation.resume()
                log(
                    "Resumed", id: key,
                    file: file, function: function, line: line
                )
                return
            }

            continuations[key] = continuation
            log("Tracking", id: key, file: file, function: function, line: line)
        }
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map.
    ///
    /// - Parameters:
    ///   - continuation: The continuation to remove and cancel.
    ///   - key: The key in the map.
    ///   - file: The file remove request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function remove request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line remove request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func removeContinuation(
        _ continuation: Continuation,
        withKey key: UUID,
        file: String, function: String, line: UInt
    ) {
        locker.perform {
            continuations.removeValue(forKey: key)
            guard !continuation.resumed else {
                log(
                    "Already resumed, not cancelling", id: key,
                    file: file, function: function, line: line
                )
                return
            }

            continuation.cancel()
            log(
                "Cancelled", id: key,
                file: file, function: function, line: line
            )
        }
    }

    /// Starts operation asynchronously
    /// as part of a new top-level task on behalf of the current actor.
    ///
    /// - Parameters:
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    public func signal(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.start()
        log("Started", file: file, function: function, line: line)
    }

    /// Waits for operation to complete successfully or cancelled.
    ///
    /// Only waits asynchronously, if operation is executing,
    /// until it is completed or cancelled.
    ///
    /// - Parameters:
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func wait(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        guard !isFinished else {
            log("Finished", file: file, function: function, line: line)
            return
        }

        let key = UUID()
        log("Waiting", id: key, file: file, function: function, line: line)
        try await withPromisedContinuation(
            withKey: key,
            file: file, function: function, line: line
        )
        log("Finished", id: key, file: file, function: function, line: line)
    }
}

/// An error that indicates that operation result
/// requested without starting operation.
///
/// Error is thrown by ``TaskOperation/result``
/// if the operation hasn't been started yet with either
/// ``TaskOperation/start()`` or
/// ``TaskOperation/signal(file:function:line:)``.
@frozen
public struct EarlyInvokeError: Error, Sendable {}

/// A set of behaviors for ``TaskOperation``s,
/// such as the task type and task completion behavior.
///
/// ``TaskOperation`` determines the execution behavior of
/// provided action as task based on the provided flags.
@frozen
public struct TaskOperationFlags: OptionSet, Sendable {
    /// Indicates to ``TaskOperation``, completion of unstructured tasks
    /// created as part of provided operation should be tracked.
    ///
    /// If provided, GCD operation only completes if the provided asynchronous action
    /// and all of its created unstructured task completes.
    /// Otherwise, operation completes if the provided action itself completes.
    public static let trackUnstructuredTasks = Self.init(rawValue: 1 << 0)
    /// Indicates to ``TaskOperation`` to disassociate action from the current execution context
    /// by running as a new detached task.
    ///
    /// Provided action is executed asynchronously as part of a new top-level task,
    /// with the provided task priority and without inheriting actor context that started
    /// the GCD operation.
    public static let detached = Self.init(rawValue: 1 << 1)

    /// The type used to track completion of provided operation and unstructured tasks created in it.
    private typealias Tracker = TaskTracker

    /// Runs the given throwing operation asynchronously as part of a new top-level task
    /// based on the current flags indicating whether to on behalf of the current actor
    /// and whether to track unstructured tasks created in provided operation.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task that operation executes.
    ///               Pass `nil` to use the priority from `Task.currentPriority`
    ///               of task that starts the operation.
    ///   - operation: The asynchronous operation to execute.
    ///   - completion: The action to invoke when task completes.
    ///
    /// - Returns: A reference to the task.
    fileprivate func createTask<R: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> R,
        onComplete completion: @escaping @Sendable () -> Void
    ) -> Task<R, Error> {
        typealias LocalTask = Task<R, Error>
        typealias ThrowingAction = @Sendable () async throws -> R
        typealias TaskInitializer = (TaskPriority?, ThrowingAction) -> LocalTask

        let initializer =
            self.contains(.detached)
            ? LocalTask.detached
            : LocalTask.init
        return initializer(priority) {
            return self.contains(.trackUnstructuredTasks)
                ? try await Tracker.$current.withValue(
                    .init(onComplete: completion),
                    operation: operation
                )
                : try await {
                    defer { completion() }
                    return try await operation()
                }()
        }
    }

    /// The corresponding value of the raw type.
    ///
    /// A new instance initialized with rawValue will be equivalent to this instance.
    /// For example:
    /// ```swift
    /// print(TaskOperationFlags(rawValue: 1 << 1) == TaskOperationFlags.detached)
    /// // Prints "true"
    /// ```
    public let rawValue: UInt8
    /// Creates a new flag from the given raw value.
    ///
    /// - Parameter rawValue: The raw value of the flag set to create.
    /// - Returns: The newly created flag set.
    ///
    /// - Note: Do not use this method to create flag,
    ///         use the default flags provided instead.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

#if canImport(Logging)
import Logging

extension TaskOperation {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)",
            "priority": "\(priority != nil ? "\(priority!)" : "nil")",
            "flags": "\(flags)",
            "executing": "\(isExecuting)",
            "cancelled": "\(isCancelled)",
            "finished": "\(isFinished)",
        ]
    }
}
#endif
