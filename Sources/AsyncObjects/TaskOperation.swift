#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif
import Dispatch

/// An object that bridges asynchronous work under structured concurrency
/// to Grand Central Dispatch (GCD or `libdispatch`) as `Operation`.
///
/// Using this object traditional `libdispatch` APIs can be used along with structured concurrency
/// making concurrent task management flexible in terms of managing dependencies.
///
/// You can start the operation by adding it to an `OperationQueue`,
/// or by manually calling the ``signal()`` or ``start()`` method.
/// Wait for operation completion asynchronously by calling ``wait()`` method
/// or its timeout variation ``wait(forNanoseconds:)``:
///
/// ```swift
/// // create operation with async action
/// let operation = TaskOperation { try await Task.sleep(nanoseconds: 1_000_000_000) }
/// // start operation to execute action
/// operation.start() // operation.signal()
///
/// // wait for operation completion asynchrnously, fails only if task cancelled
/// try await operation.wait()
/// // or wait with some timeout
/// try await operation.wait(forNanoseconds: 1_000_000_000)
/// // or wait synchronously for completion
/// operation.waitUntilFinished()
/// ```
public final class TaskOperation<R: Sendable>: Operation, AsyncObject,
    @unchecked Sendable
{
    /// The asynchronous action to perform as part of the operation..
    private let underlyingAction: @Sendable () async throws -> R
    /// The top-level task that executes asynchronous action provided
    /// on behalf of the actor where operation started.
    private var execTask: Task<R, Error>?
    /// The platform dependent lock used to
    /// synchronize data access and modifications.
    @usableFromInline
    let locker: Locker

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
    /// A Boolean value indicating whether the operation has been cancelled.
    ///
    /// Returns whether the underlying top-level task is cancelled or not.
    /// The default value of this property is `false`.
    /// Calling the ``cancel()`` method of this object sets the value of this property to `true`.
    public override var isCancelled: Bool { execTask?.isCancelled ?? false }

    /// Private store for boolean value indicating whether the operation is currently executing.
    @usableFromInline
    var _isExecuting: Bool = false
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
    var _isFinished: Bool = false
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
        get async { (await execTask?.result) ?? .failure(EarlyInvokeError()) }
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
        let final = { @Sendable[weak self] in self?._finish(); return }
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
        execTask?.cancel()
        _finish()
    }

    /// Moves this operation to finished state.
    ///
    /// Must be called either when operation completes or cancelled.
    @inlinable
    func _finish() {
        isExecuting = false
        isFinished = true
    }

    // MARK: AsyncObject
    /// The suspended tasks continuation type.
    @usableFromInline
    typealias Continuation = SafeContinuation<GlobalContinuation<Void, Error>>
    /// The continuations stored with an associated key for all the suspended task that are waiting for operation completion.
    @usableFromInline
    private(set) var continuations: [UUID: Continuation] = [:]

    /// Add continuation with the provided key in `continuations` map.
    ///
    /// - Parameters:
    ///   - continuation: The `continuation` to add.
    ///   - key: The key in the map.
    @inlinable
    func _addContinuation(
        _ continuation: Continuation,
        withKey key: UUID
    ) {
        locker.perform {
            guard !continuation.resumed else { return }
            if isFinished { continuation.resume(); return }
            continuations[key] = continuation
        }
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    func _removeContinuation(withKey key: UUID) {
        locker.perform { continuations.removeValue(forKey: key) }
    }

    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `_removeContinuation`.
    ///
    /// Spins up a new continuation and requests to track it with key by invoking `_addContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `_removeContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    func _withPromisedContinuation() async throws {
        let key = UUID()
        try await Continuation.withCancellation(synchronizedWith: locker) {
            Task { [weak self] in self?._removeContinuation(withKey: key) }
        } operation: { continuation in
            Task { [weak self] in
                self?._addContinuation(continuation, withKey: key)
            }
        }
    }

    /// Starts operation asynchronously
    /// as part of a new top-level task on behalf of the current actor.
    @Sendable
    public func signal() {
        self.start()
    }

    /// Waits for operation to complete successfully or cancelled.
    ///
    /// Only waits asynchronously, if operation is executing,
    /// until it is completed or cancelled.
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func wait() async throws {
        guard !isFinished else { return }
        try await _withPromisedContinuation()
    }
}

/// An error that indicates that operation result
/// requested without starting operation.
///
/// Error is thrown by ``TaskOperation/result``
/// if the operation hasn't been started yet with either
/// ``TaskOperation/start()`` or ``TaskOperation/signal()``.
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
