@preconcurrency import Foundation
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
/// or its timeout variation ``wait(forNanoseconds:)``.
public final class TaskOperation<R: Sendable>: Operation, AsyncObject,
    @unchecked Sendable
{
    /// The type used to track completion of provided operation and their child tasks.
    private typealias Tracker = TaskTracker
    /// The asynchronous action to perform as part of the operation..
    private let underlyingAction: @Sendable () async throws -> R
    /// The top-level task that executes asynchronous action provided
    /// on behalf of the actor where operation started.
    private var execTask: Task<R, Error>?
    /// The platform dependent lock used to
    /// synchronize data access and modifications.
    @usableFromInline
    let locker: Locker
    /// The priority of top-level task executed.
    ///
    /// In case of `nil` priority from `Task.currentPriority`
    /// of task that starts the operation used.
    public let priority: TaskPriority?
    /// If completion of child tasks created as part of provided task
    /// should be tracked.
    ///
    /// If true, operation only completes if the provided asynchronous action
    /// and all of its child task completes. Otherwise, operation completes if the
    /// provided action itself completes.
    public let shouldTrackChildTasks: Bool

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
    ///   - shouldTrackChildTasks: Whether to wait for all the child tasks created
    ///                            as part of provided asynchronous action.
    ///   - locker: The locker to use to synchronize property read and mutations.
    ///             New lock object is created in case none provided.
    ///   - priority: The priority of the task that operation executes.
    ///               Pass `nil` to use the priority from `Task.currentPriority`
    ///               of task that starts the operation.
    ///   - operation: The asynchronous operation to execute.
    ///
    /// - Returns: The newly created asynchronous operation.
    public init(
        trackChildTasks shouldTrackChildTasks: Bool = false,
        synchronizedWith locker: Locker = .init(),
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> R
    ) {
        self.shouldTrackChildTasks = shouldTrackChildTasks
        self.locker = locker
        self.priority = priority
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
        execTask = Task(priority: priority) { [weak self] in
            guard
                let action = self?.underlyingAction,
                let shouldTrackChildTasks = self?.shouldTrackChildTasks
            else { throw CancellationError() }
            let final = { @Sendable[weak self] in self?._finish(); return;  }
            return shouldTrackChildTasks
                ? try await Tracker.$current.withValue(
                    .init(onComplete: final),
                    operation: action
                )
                : try await {
                    defer { final() }
                    return try await action()
                }()
        }
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
    typealias Continuation = GlobalContinuation<Void, Error>
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
            if _isFinished { continuation.resume(); return }
            continuations[key] = continuation
        }
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    func _removeContinuation(withKey key: UUID) {
        locker.perform {
            let continuation = continuations.removeValue(forKey: key)
            continuation?.cancel()
        }
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
        try await withTaskCancellationHandler { [weak self] in
            self?._removeContinuation(withKey: key)
        } operation: { () -> Continuation.Success in
            try await Continuation.with { continuation in
                self._addContinuation(continuation, withKey: key)
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
    @Sendable
    public func wait() async {
        guard !isFinished else { return }
        try? await _withPromisedContinuation()
    }
}

/// An error that indicates that operation result
/// requested without starting operation.
///
/// Error is thrown by ``TaskOperation/result``
/// if the operation hasn't been started yet with either
/// ``TaskOperation/start()`` or ``TaskOperation/signal()``.
public struct EarlyInvokeError: Error, Sendable {}
