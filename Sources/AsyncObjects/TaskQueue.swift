#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif

import OrderedCollections

/// An object that acts as a concurrent queue executing submitted tasks concurrently.
///
/// You can use the ``exec(priority:flags:file:function:line:operation:)-et``
/// or its non-throwing/non-cancellable version to run tasks concurrently.
/// Additionally, you can provide priority of task and ``Flags``
/// to customize execution of submitted operation.
///
/// ```swift
/// // create a queue with some priority processing async actions
/// let queue = TaskQueue()
/// // add operations to queue to be executed asynchronously
/// queue.addTask {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
/// // or wait asynchronously for operation to be executed on queue
/// // the provided operation cancelled if invoking task cancelled
/// try await queue.exec {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
///
/// // provide additional flags for added operations
/// // execute operation as a barrier
/// queue.addTask(flags: .barrier) {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
/// // execute operation as a detached task
/// queue.addTask(flags: .detached) {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
/// // combine multiple flags for operation execution
/// queue.addTask(flags: [.barrier, .detached]) {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
/// ```
public actor TaskQueue: AsyncObject, LoggableActor {
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
        internal var isBlockEnabled: Bool {
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
        internal func choosePriority(
            fromContext context: TaskPriority?,
            andWork work: TaskPriority?
        ) -> TaskPriority? {
            let result: TaskPriority?
            let priorities =
                (self.contains(.detached)
                ? [work, context]
                : [work, context, Task.currentPriority])
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
        internal func wait(forCurrent current: UInt) -> Bool {
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
    internal typealias Continuation = TrackedContinuation<
        GlobalContinuation<Void, Error>
    >
    /// A mechanism to queue tasks in ``TaskQueue``, to be resumed when queue is freed
    /// and provided flags are satisfied.
    @usableFromInline
    internal typealias QueuedContinuation = (value: Continuation, flags: Flags)

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
    internal func shouldWait(whenFlags flags: Flags) -> Bool {
        return blocked
            || !queue.isEmpty
            || flags.wait(forCurrent: currentRunning)
    }

    /// Resume provided continuation with additional changes based on the associated flags.
    ///
    /// - Parameters:
    ///   - continuation: The queued continuation to resume.
    ///   - key: The key in the continuation queue.
    ///   - file: The file resume request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function resume request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line resume request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: Whether queue is free to proceed scheduling other tasks.
    @inlinable
    @discardableResult
    internal func resumeQueuedContinuation(
        _ continuation: QueuedContinuation,
        atKey key: UUID,
        file: String, function: String, line: UInt
    ) -> Bool {
        defer {
            log(
                "Resumed", flags: continuation.flags, id: key,
                file: file, function: function, line: line
            )
        }

        currentRunning += 1
        continuation.value.resume()
        guard continuation.flags.isBlockEnabled else { return true }
        blocked = true
        return false
    }

    /// Add continuation with the provided key and associated flags to queue.
    ///
    /// - Parameters:
    ///   - continuation: The continuation and flags to add to queue.
    ///   - key: The key in the continuation queue.
    ///   - file: The file queue request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function queue request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line queue request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - preinit: The pre-initialization handler to run
    ///              in the beginning of this method.
    ///
    /// - Important: The pre-initialization handler must run
    ///              before any logic in this method.
    @inlinable
    internal func queueContinuation(
        _ continuation: QueuedContinuation,
        atKey key: UUID,
        file: String, function: String, line: UInt,
        preinit: @Sendable () -> Void
    ) {
        preinit()
        log(
            "Adding", flags: continuation.flags, id: key,
            file: file, function: function, line: line
        )

        guard !continuation.value.resumed else {
            log(
                "Already resumed, not tracking",
                flags: continuation.flags, id: key,
                file: file, function: function, line: line
            )
            return
        }

        guard shouldWait(whenFlags: continuation.flags) else {
            resumeQueuedContinuation(
                continuation, atKey: key,
                file: file, function: function, line: line
            )
            return
        }

        queue[key] = continuation
        log(
            "Tracking", flags: continuation.flags, id: key,
            file: file, function: function, line: line
        )
    }

    /// Remove continuation associated with provided key from queue.
    ///
    /// - Parameters:
    ///   - continuation: The continuation and flags to remove and cancel.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - key: The key in the continuation queue.
    ///   - file: The file remove request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function remove request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line remove request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func dequeueContinuation(
        _ continuation: QueuedContinuation,
        withKey key: UUID,
        file: String, function: String, line: UInt
    ) {
        let (continuation, flags) = continuation
        log(
            "Removing", flags: flags, id: key,
            file: file, function: function, line: line
        )

        queue.removeValue(forKey: key)
        guard !continuation.resumed else {
            log(
                "Already resumed, not cancelling", flags: flags, id: key,
                file: file, function: function, line: line
            )
            return
        }

        continuation.cancel()
        log(
            "Cancelled", flags: flags, id: key,
            file: file, function: function, line: line
        )
    }

    /// Unblock queue allowing other queued tasks to run
    /// after blocking task completes successfully or cancelled.
    ///
    /// Updates the ``blocked`` flag and starts queued tasks
    /// in order of their addition if any tasks are queued.
    ///
    /// - Parameters:
    ///   - file: The file unblock request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The unblock resume request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line unblock request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func unblockQueue(file: String, function: String, line: UInt) {
        blocked = false
        resumeQueuedTasks(file: file, function: function, line: line)
    }

    /// Signals completion of operation to the queue
    /// by decrementing ``currentRunning`` count.
    ///
    /// Updates the ``currentRunning`` count and starts
    /// queued tasks in order of their addition if any queued.
    ///
    /// - Parameters:
    ///   - file: The file signal request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func signalCompletion(file: String, function: String, line: UInt) {
        defer { resumeQueuedTasks(file: file, function: function, line: line) }
        guard currentRunning > 0 else { return }
        currentRunning -= 1
    }

    /// Resumes queued tasks when queue isn't blocked
    /// and operation flags preconditions satisfied.
    ///
    /// - Parameters:
    ///   - file: The file resume request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function resume request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line resume request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func resumeQueuedTasks(
        file: String, function: String, line: UInt
    ) {
        while let (key, continuation) = queue.elements.first,
            !blocked,
            !continuation.flags.wait(forCurrent: currentRunning)
        {
            queue.removeFirst()
            guard
                resumeQueuedContinuation(
                    continuation, atKey: key,
                    file: file, function: function, line: line
                )
            else { break }
        }
    }

    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `dequeueContinuation`.
    ///
    /// Spins up a new continuation and requests to track it on queue with key by invoking `queueContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `dequeueContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Parameters:
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - key: The key associated to task, that requested suspension.
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    internal func withPromisedContinuation(
        flags: Flags = [],
        withKey key: UUID,
        file: String, function: String, line: UInt
    ) async throws {
        try await Continuation.withCancellation(id: key) { continuation in
            Task { [weak self] in
                await self?.dequeueContinuation(
                    (value: continuation, flags: flags), withKey: key,
                    file: file, function: function, line: line
                )
            }
        } operation: { continuation, preinit in
            Task { [weak self] in
                await self?.queueContinuation(
                    (value: continuation, flags: flags), atKey: key,
                    file: file, function: function, line: line,
                    preinit: preinit
                )
            }
        }
    }

    /// Executes the given operation asynchronously based on the priority and flags provided.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - key: Optional key associated with task.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    @inlinable
    internal func run<T: Sendable>(
        with priority: TaskPriority?,
        flags: Flags,
        withKey key: UUID?,
        file: String, function: String, line: UInt,
        operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        defer { signalCompletion(file: file, function: function, line: line) }
        typealias LocalTask = Task<T, Error>
        let taskPriority = flags.choosePriority(
            fromContext: self.priority,
            andWork: priority
        )

        log(
            "Executing", flags: flags, id: key,
            file: file, function: function, line: line
        )
        return flags.contains(.detached)
            ? try await LocalTask.withCancellableDetachedTask(
                priority: taskPriority,
                operation: operation
            )
            : try await LocalTask.withCancellableTask(
                priority: taskPriority,
                operation: operation
            )
    }

    /// Executes the given operation asynchronously based on the priority
    /// while blocking queue until completion.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - key: Optional key associated with task.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    @inlinable
    internal func runBlocking<T: Sendable>(
        with priority: TaskPriority?,
        flags: Flags,
        withKey key: UUID?,
        file: String, function: String, line: UInt,
        operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        defer { unblockQueue(file: file, function: function, line: line) }
        blocked = true
        return try await run(
            with: priority, flags: flags, withKey: key,
            file: file, function: function, line: line,
            operation: operation
        )
    }

    /// Creates a new concurrent task queue for running submitted tasks concurrently
    /// with the default priority of the submitted tasks.
    ///
    /// - Parameter priority: The default priority of the tasks submitted to queue.
    ///                       Pass `nil` to use the priority from
    ///                       execution context(`Task.currentPriority`)
    ///                       for non-detached tasks.
    ///
    /// - Returns: The newly created concurrent task queue.
    public init(priority: TaskPriority? = nil) {
        self.priority = priority
    }

    // TODO: Explore alternative cleanup for actor
    // deinit { self.queue.forEach { $1.value.cancel() } }

    /// Executes the given operation asynchronously based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later. If the task is cancelled
    /// while waiting for execution, the cancellation handler is invoked with `CancellationError`,
    /// which determines whether to continue executing task or throw error.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`) for non-detached tasks.
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///   - cancellation: The cancellation handler invoked if continuation is cancelled.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: Error from provided operation or the cancellation handler.
    @discardableResult
    @inlinable
    internal func execHelper<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        file: String, function: String, line: UInt,
        operation: @Sendable @escaping () async throws -> T,
        cancellation: (Error) throws -> Void
    ) async rethrows -> T {
        func runTask(
            withKey key: UUID? = nil,
            _ operation: @Sendable @escaping () async throws -> T
        ) async rethrows -> T {
            return flags.isBlockEnabled
                ? try await runBlocking(
                    with: priority, flags: flags, withKey: key,
                    file: file, function: function, line: line,
                    operation: operation
                )
                : try await run(
                    with: priority, flags: flags, withKey: key,
                    file: file, function: function, line: line,
                    operation: operation
                )
        }

        guard self.shouldWait(whenFlags: flags) else {
            currentRunning += 1
            return try await runTask(operation)
        }

        let key = UUID()
        log(
            "Waiting", flags: flags, id: key,
            file: file, function: function, line: line
        )

        do {
            try await withPromisedContinuation(
                flags: flags, withKey: key,
                file: file, function: function, line: line
            )
        } catch {
            try cancellation(error)
        }

        defer {
            log(
                "Executed", flags: flags, id: key,
                file: file, function: function, line: line
            )
        }
        return try await runTask(withKey: key, operation)
    }

    /// Executes the given throwing operation asynchronously based on the priority and flags.
    ///
    /// Immediately runs the provided operation if queue isn't blocked by any task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed. Pass `nil` to use the priority
    ///               from execution context(`Task.currentPriority`) for non-detached tasks.
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The throwing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    ///
    /// - Note: If task that added the operation to queue is cancelled,
    ///         the provided operation also cancelled cooperatively if already started
    ///         or the operation execution is skipped if only queued and not started.
    @Sendable
    @discardableResult
    public func exec<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        return try await execHelper(
            priority: priority, flags: flags,
            file: file, function: function, line: line,
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
    ///               from execution context(`Task.currentPriority`) for non-detached tasks.
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The non-throwing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    @Sendable
    @discardableResult
    public func exec<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        return await execHelper(
            priority: priority, flags: flags,
            file: file, function: function, line: line,
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
    ///               from execution context(`Task.currentPriority`) for non-detached tasks.
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The throwing operation to perform.
    @Sendable
    public nonisolated func addTask<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @Sendable @escaping () async throws -> T
    ) {
        Task {
            try await exec(
                priority: priority, flags: flags,
                file: file, function: function, line: line,
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
    ///               from execution context(`Task.currentPriority`) for non-detached tasks.
    ///   - flags: Additional attributes to apply when executing the operation.
    ///            For a list of possible values, see ``Flags``.
    ///   - file: The file execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function execution request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line execution request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The non-throwing operation to perform.
    @Sendable
    public nonisolated func addTask<T: Sendable>(
        priority: TaskPriority? = nil,
        flags: Flags = [],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @Sendable @escaping () async -> T
    ) {
        Task {
            await exec(
                priority: priority, flags: flags,
                file: file, function: function, line: line,
                operation: operation
            )
        }
    }

    /// Signalling on queue does nothing.
    /// Only added to satisfy ``AsyncObject`` requirements.
    ///
    /// - Parameters:
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    public nonisolated func signal(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { /* Do nothing */  }

    /// Waits for execution turn on queue.
    ///
    /// Only waits asynchronously, if queue is locked by a barrier task,
    /// until the suspended task's turn comes to be resumed.
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
        try await exec(
            file: file, function: function, line: line
        ) { try await Task.sleep(nanoseconds: 0) }
    }
}

#if canImport(Logging)
import Logging

extension TaskQueue {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)(\(Unmanaged.passUnretained(self).toOpaque()))",
            "blocked": "\(blocked)",
            "current_running": "\(currentRunning)",
            "priority": "\(priority != nil ? "\(priority!)" : "nil")",
        ]
    }

    /// Log a message attaching the default type specific metadata
    /// and optional identifier.
    ///
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE` is set log level is set to `trace`.
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG` is set log level is set to `debug`.
    /// Otherwise log level is set to `info`.
    ///
    /// - Parameters:
    ///   - message: The message to be logged.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - id: Optional identifier associated with message.
    ///   - file: The file this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#fileID`).
    ///   - function: The function this log message originates from (there's usually
    ///               no need to pass it explicitly as it defaults to `#function`).
    ///   - line: The line this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#line`).
    @inlinable
    func log(
        _ message: @autoclosure () -> Logger.Message,
        flags: Flags,
        id: UUID? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        var metadata = self.metadata
        metadata["flags"] = "\(flags)"
        if let id = id { metadata["id"] = "\(id)" }
        logger.log(
            level: level, message(), metadata: metadata,
            file: file, function: function, line: line
        )
    }
}
#else
extension TaskQueue {
    /// Log a message attaching the default type specific metadata
    /// and optional identifier.
    ///
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE` is set log level is set to `trace`.
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG` is set log level is set to `debug`.
    /// Otherwise log level is set to `info`.
    ///
    /// - Parameters:
    ///   - message: The message to be logged.
    ///   - flags: The flags associated that determine the execution behavior of task.
    ///   - id: Optional identifier associated with message.
    ///   - file: The file this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#fileID`).
    ///   - function: The function this log message originates from (there's usually
    ///               no need to pass it explicitly as it defaults to `#function`).
    ///   - line: The line this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#line`).
    @inlinable
    nonisolated func log(
        _ message: @autoclosure () -> String,
        flags: Flags,
        id: UUID? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { /* Do nothing */  }
}
#endif
