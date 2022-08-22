@preconcurrency import Foundation
import OrderedCollections

/// An object that acts as a concurrent queue executing submitted tasks concurrently.
///
/// You can use the ``exec(priority:flags:operation:)-92nww``
/// or its non-throwing/non-cancellable version to run tasks concurrently.
/// Additionally, you can provide priority of task and ``Flags``
/// to customize execution of submitted operation.
public actor TaskQueue: AsyncObject {
    /// A set of behaviors for operations, such as its priority and whether to create a barrier
    /// or spawn a new detached task.
    ///
    /// The ``TaskQueue`` determines when and how to add operations to queue
    /// based on the provided flags.
    public struct Flags: OptionSet, Sendable {
        /// Prefer the priority associated with the operation only if it is higher
        /// than the current execution context.
        ///
        /// This flag prioritizes the operation's priority over the one associated
        /// with the current execution context, as long as doing so does not lower the priority.
        public static let enforce = Self.init(rawValue: 1 << 0)
        /// Indicates to disassociate operation from the current execution context
        /// by running as a new detached task.
        ///
        /// Operation is executed asynchronously as part of a new top-level task,
        /// with the provided task priority.
        public static let detached = Self.init(rawValue: 1 << 1)
        /// Block the queue when operation is submitted, until operation is completed.
        ///
        /// When submitted to queue, an operation with this flag blocks the queue if queue is free.
        /// If queue is already blocked, then the operation waits for queue to be freed for its turn.
        /// Operations submitted prior to the block aren't affected and execute to completion,
        /// while later submitted operations wait for queue to be freed. Once the block operation finishes,
        /// the queue returns to scheduling operations that were submitted after the block.
        ///
        /// - Note: In presence of ``barrier`` flag this flag is ignored
        ///         and priority is given to ``barrier`` flag.
        public static let block = Self.init(rawValue: 1 << 2)
        /// Cause the operation to act as a barrier when submitted to queue.
        ///
        /// When submitted to queue, an operation with this flag acts as a barrier.
        /// Operations submitted prior to the barrier execute to completion,
        /// at which point the barrier operation executes. Once the barrier operation finishes,
        /// the queue returns to scheduling operations that were submitted after the barrier.
        ///
        /// - Note: This flag is given higher priority than ``block`` flag if both present.
        public static let barrier = Self.init(rawValue: 1 << 3)

        /// Checks if flag for blocking queue is provided.
        ///
        /// Returns `true` if either ``barrier`` or ``block`` flag provided.
        @usableFromInline
        var isBlockEnabled: Bool {
            return self.contains(.block) || self.contains(.barrier)
        }

        /// Determines priority of the operation execution based on
        /// requested priority, queue priority and current execution context.
        ///
        /// If ``enforce`` flag is provided the maximum priority between
        /// requested priority, queue priority and current execution context is chosen.
        /// Otherwise, requested priority is used if provided or queue priority is used
        /// in absence of everything else.
        ///
        /// - Parameters:
        ///   - context: The default priority for queue.
        ///   - work: The execution priority of operation requested.
        ///
        /// - Returns: The determined priority of operation to be executed,
        ///            based on provided flags.
        @usableFromInline
        func choosePriority(
            fromContext context: TaskPriority?,
            andWork work: TaskPriority?
        ) -> TaskPriority? {
            let result: TaskPriority?
            let priorities = [work, context, Task.currentPriority]
                .compactMap { $0 }
                .sorted { $0.rawValue > $1.rawValue }
            if self.contains(.enforce) {
                result = priorities.first
            } else if let work = work {
                result = work
            } else {
                result = context
            }
            return result
        }

        /// Checks whether to suspend new task based on
        /// currently running operations on queue.
        ///
        /// If ``barrier`` flag is present and currently queue is running any operations,
        /// newly added task is suspended until queue isn't running any operation.
        ///
        /// - Parameter current: The currently running operations count for queue.
        ///
        /// - Returns: Whether to suspend newly added task.
        @usableFromInline
        func wait(forCurrent current: UInt) -> Bool {
            return self.contains(.barrier) ? current > 0 : false
        }

        /// The corresponding value of the raw type.
        ///
        /// A new instance initialized with rawValue will be equivalent to this instance.
        /// For example:
        /// ```swift
        /// print(Flags(rawValue: 1 << 0) == Flags.enforce)
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

    /// The suspended tasks continuation type.
    @usableFromInline
    typealias Continuation = GlobalContinuation<Void, Error>
    /// A mechanism to queue tasks in ``TaskQueue``, to be resumed when queue is freed
    /// and provided flags are satisfied.
    @usableFromInline
    typealias QueuedContinuation = (value: Continuation, flags: Flags)
    /// The list of tasks currently queued and would be resumed one by one when current barrier task ends.
    @usableFromInline
    private(set) var queue: OrderedDictionary<UUID, QueuedContinuation> = [:]
    /// Indicates whether queue is locked by any task currently running.
    public var blocked: Bool = false
    /// Current count of the countdown.
    ///
    /// If the current count becomes less or equal to limit, queued tasks
    /// are resumed from suspension until current count exceeds limit.
    public var currentRunning: UInt = 0
    /// The default priority with which new tasks on the queue are started.
    public let priority: TaskPriority?

    /// Checks whether to wait for queue to be free
    /// to continue with execution based on provided flags.
    ///
    /// - Parameter flags: The flags provided for new task.
    /// - Returns: Whether to wait to be resumed later.
    @inlinable
    func _wait(whenFlags flags: Flags) -> Bool {
        return blocked
            || !queue.isEmpty
            || flags.wait(forCurrent: currentRunning)
    }

    /// Add continuation with the provided key and associated flags to queue.
    ///
    /// - Parameters:
    ///   - flags: The flags associated with continuation operation.
    ///   - key: The key in the continuation queue.
    ///   - continuation: The continuation to add to queue.
    @inlinable
    func _queueContinuation(
        withFlags flags: Flags = [],
        atKey key: UUID = .init(),
        _ continuation: Continuation
    ) {
        queue[key] = (value: continuation, flags: flags)
    }

    /// Remove continuation associated with provided key from queue.
    ///
    /// - Parameter key: The key in the continuation queue.
    @inlinable
    func _dequeueContinuation(withKey key: UUID) {
        let continuation = queue.removeValue(forKey: key)
        continuation?.value.cancel()
    }

    /// Unblock queue allowing other queued tasks to run
    /// after blocking task completes successfully or cancelled.
    ///
    /// Updates the ``blocked`` flag and starts queued tasks
    /// in order of their addition if any tasks are queued.
    @inlinable
    func _unblockQueue() {
        blocked = false
        _resumeQueuedTasks()
    }

    /// Signals completion of operation to the queue
    /// by decrementing ``currentRunning`` count.
    ///
    /// Updates the ``currentRunning`` count and starts
    /// queued tasks in order of their addition if any queued.
    @inlinable
    func _signalCompletion() {
        defer { _resumeQueuedTasks() }
        guard currentRunning > 0 else { return }
        currentRunning -= 1
    }

    /// Resumes queued tasks when queue isn't blocked
    /// and operation flags preconditions satisfied.
    @inlinable
    func _resumeQueuedTasks() {
        while let (_, (continuation, flags)) = queue.elements.first,
            !blocked,
            !flags.wait(forCurrent: currentRunning)
        {
            queue.removeFirst()
            currentRunning += 1
            continuation.resume()
            if flags.isBlockEnabled {
                blocked = true
                break
            }
        }
    }

    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `_dequeueContinuation`.
    ///
    /// Spins up a new continuation and requests to track it on queue with key by invoking `_queueContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `_dequeueContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Parameter flags: The flags associated that determine the execution behavior of task.
    ///
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    func _withPromisedContinuation(flags: Flags = []) async throws {
        let key = UUID()
        try await withTaskCancellationHandler { [weak self] in
            Task { [weak self] in
                await self?._dequeueContinuation(withKey: key)
            }
        } operation: { () -> Continuation.Success in
            try await Continuation.with { continuation in
                self._queueContinuation(
                    withFlags: flags,
                    atKey: key,
                    continuation
                )
            }
        }
    }

    /// Executes the given operation asynchronously based on the priority and flags provided.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    @inlinable
    func _run<T: Sendable>(
        with priority: TaskPriority?,
        flags: Flags,
        operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        defer { _signalCompletion() }
        typealias LocalTask = Task<T, Error>
        let taskPriority = flags.choosePriority(
            fromContext: self.priority,
            andWork: priority
        )
        let taskInitializer =
            flags.contains(.detached)
            ? LocalTask.detached(priority:operation:)
            : LocalTask.init(priority:operation:)

        let task = taskInitializer(taskPriority, operation)
        return try await withTaskCancellationHandler(
            handler: {
                task.cancel()
            },
            operation: {
                return try await task.value
            })
    }

    /// Executes the given operation asynchronously based on the priority
    /// while blocking queue until completion.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    @inlinable
    func _runBlocking<T: Sendable>(
        with priority: TaskPriority?,
        flags: Flags,
        operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        defer { _unblockQueue() }
        blocked = true
        return try await _run(
            with: priority,
            flags: flags,
            operation: operation
        )
    }

    /// Creates a new concurrent task queue for running submitted tasks concurrently
    /// with the default priority of the submitted tasks.
    ///
    /// - Parameter priority: The default priority of the tasks submitted to queue.
    ///                       Pass `nil` to use the priority from
    ///                       execution context(`Task.currentPriority`).
    ///
    /// - Returns: The newly created concurrent task queue.
    public init(priority: TaskPriority? = nil) {
        self.priority = priority
    }

    deinit { self.queue.forEach { $1.value.cancel() } }

    /// Executes the given operation asynchronously based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later. If the task is cancelled
    /// while waiting for execution, the cancellation handler is invoked with `CancellationError`,
    /// which determines whether to continue executing task or throw error.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`).
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - operation: The operation to perform.
    ///   - cancellation: The cancellation handler invoked if continuation is cancelled.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: Error from provided operation or the cancellation handler.
    @discardableResult
    @inlinable
    public func _execHelper<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async throws -> T,
        cancellation: (Error) throws -> Void
    ) async rethrows -> T {
        func runTask(
            _ operation: @Sendable @escaping () async throws -> T
        ) async rethrows -> T {
            return flags.isBlockEnabled
                ? try await _runBlocking(
                    with: priority,
                    flags: flags,
                    operation: operation
                )
                : try await _run(
                    with: priority,
                    flags: flags,
                    operation: operation
                )
        }

        guard self._wait(whenFlags: flags) else {
            currentRunning += 1
            return try await runTask(operation)
        }

        do {
            try await _withPromisedContinuation(flags: flags)
        } catch {
            try cancellation(error)
        }

        return try await runTask(operation)
    }

    /// Executes the given throwing operation asynchronously based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`).
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - operation: The throwing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    ///
    /// - Note: If task that added the operation to queue is cancelled,
    ///         the provided operation also cancelled cooperatively if already started
    ///         or the operation execution is skipped if only queued and not started.
    @discardableResult
    public func exec<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        return try await _execHelper(
            priority: priority,
            flags: flags,
            operation: operation
        ) { throw $0 }
    }

    /// Executes the given non-throwing operation asynchronously based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`).
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - operation: The non-throwing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    @discardableResult
    public func exec<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        return await _execHelper(
            priority: priority,
            flags: flags,
            operation: operation
        ) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }

    /// Adds the given throwing operation to queue to be executed asynchronously
    /// based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`).
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - operation: The throwing operation to perform.
    public nonisolated func addTask<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async throws -> T
    ) {
        Task {
            try await exec(
                priority: priority,
                flags: flags,
                operation: operation
            )
        }
    }

    /// Adds the given non-throwing operation to queue to be executed asynchronously
    /// based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`).
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - operation: The non-throwing operation to perform.
    public nonisolated func addTask<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        operation: @Sendable @escaping () async -> T
    ) {
        Task {
            await exec(
                priority: priority,
                flags: flags,
                operation: operation
            )
        }
    }

    /// Signalling on queue does nothing.
    /// Only added to satisfy ``AsyncObject`` requirements.
    public func signal() {
        // Do nothing
    }

    /// Waits for execution turn on queue.
    ///
    /// Only waits asynchronously, if queue is locked by a barrier task,
    /// until the suspended task's turn comes to be resumed.
    @Sendable
    public func wait() async {
        await exec { /*Do nothing*/  }
    }
}
