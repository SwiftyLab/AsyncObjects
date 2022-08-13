import Foundation
import OrderedCollections

/// An object that acts as a concurrent queue executing submitted tasks concurrently.
///
/// You can use the ``exec(barrier:priority:operation:)-33gla`` or its non-throwing version
/// to run tasks concurrently. Optionally, you can enable the `barrier` flag for submitted task
/// to block the queue until the provided task completes execution.
public actor TaskQueue: AsyncObject {
    /// A mechanism to queue tasks in ``TaskQueue`` as a concurrent task or as a barrier task,
    /// to be resumed when queue is freed from existing barrier task.
    fileprivate struct QueuedContinuation {
        /// Whether continuation is associated with any barrier task.
        fileprivate let barrier: Bool
        /// The queued continuation to be resumed later.
        fileprivate let continuation: Continuation

        /// Creates a new continuation for task queued in ``TaskQueue``.
        ///
        /// - Parameters:
        ///   - barrier: If the continuation is associated with any barrier task.
        ///   - continuation: The continuation to be resumed on turn.
        ///
        /// - Returns: The newly created queued continuation.
        fileprivate init(
            barrier: Bool = false,
            continuation: Continuation
        ) {
            self.barrier = barrier
            self.continuation = continuation
        }

        /// Resume the provided continuation if not done already.
        ///
        /// Multiple invocations are ignored and only first invocation accepted.
        fileprivate func resume() { continuation.resume() }

        /// Resume the provided continuation if not done already.
        ///
        /// Multiple invocations are ignored and only first invocation accepted.
        fileprivate func cancel() {
            continuation.cancel()
        }
    }

    /// The execution priority of operations added to queue.
    ///
    /// The ``TaskQueue`` determines how priority information affects
    /// the way operations added to queue are started. Typically, queue just
    /// starts the operation as a new top-level task with the task priority provided.
    public enum Priority {
        /// Indicates to run the operation directly without creating as a new top-level task.
        ///
        /// Operation is executed asynchronously on behalf of the queue actor,
        /// with the current task priority.
        case none
        /// Indicates to run the operation as a new task using `Task.currentPriority`.
        ///
        /// Operation is executed asynchronously as part of a new top-level task on behalf of the current actor,
        /// with the current task priority.
        case inherit
        /// Indicates to run the operation as a new task using the provided priority.
        ///
        /// Operation is executed asynchronously as part of a new top-level task on behalf of the current actor,
        /// with the provided task priority enforced.
        case enforce(TaskPriority)
        /// Indicates to run the operation as a new detached task using the provided priority.
        ///
        /// Operation is executed asynchronously as part of a new top-level task,
        /// with the provided task priority enforced. Pass the priority `nil`
        /// to use from `Task.currentPriority`.
        case detached(TaskPriority? = nil)
    }

    /// The suspended tasks continuation type.
    fileprivate typealias Continuation = GlobalContinuation<Void, Error>
    /// The list of tasks currently queued and would be resumed one by one when current barrier task ends.
    private var queue: OrderedDictionary<UUID, QueuedContinuation> = [:]
    /// Indicates whether queue is locked by a barrier task currently running.
    public private(set) var barriered: Bool = false
    /// The default priority with which new tasks on the queue are started.
    public let priority: Priority

    /// Add continuation (both throwing and non-throwing) with the provided key in queue.
    ///
    /// - Parameters:
    ///   - barrier: Whether the continuation is associated with a barrier or blocking task.
    ///   - key: The key in the continuation queue.
    ///   - continuation: The continuation to add to queue.
    @inline(__always)
    private func queueContinuation(
        barrier: Bool = false,
        atKey key: UUID = .init(),
        _ continuation: Continuation
    ) {
        queue[key] = .init(barrier: barrier, continuation: continuation)
    }

    /// Remove continuation associated with provided key from queue.
    ///
    /// - Parameter key: The key in the continuation queue.
    @inline(__always)
    private func dequeueContinuation(withKey key: UUID) async {
        let continuation = queue.removeValue(forKey: key)
        continuation?.cancel()
    }

    /// Release barrier allowing other queued tasks to run
    /// after barrier task completes successfully or cancelled.
    ///
    /// Updates the barrier flag and starts queued tasks
    /// in order of their addition if any tasks are queued.
    @inline(__always)
    private func releaseBarrier() async {
        barriered = false
        while !queue.isEmpty {
            let (_, continuation) = queue.removeFirst()
            continuation.resume()
            if continuation.barrier { break }
        }
    }

    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `dequeueContinuation`.
    ///
    /// Spins up a new continuation and requests to track it on queue with key by invoking `queueContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `dequeueContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Parameter barrier: If the task should run as a barrier blocking queue.
    ///
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inline(__always)
    private func withPromisedContinuation(barrier: Bool = false) async throws {
        let key = UUID()
        try await withTaskCancellationHandler { [weak self] in
            Task { [weak self] in
                await self?.dequeueContinuation(withKey: key)
            }
        } operation: { () -> Continuation.Success in
            try await Continuation.with { continuation in
                self.queueContinuation(
                    barrier: barrier,
                    atKey: key,
                    continuation
                )
            }
        }
    }

    /// Executes the given operation asynchronously based on the priority.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    @inline(__always)
    private func run<T>(
        with priority: Priority,
        operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        let taskPriority: TaskPriority?
        let taskInitializer:
            (
                TaskPriority?,
                @Sendable @escaping () async throws -> T
            ) -> Task<T, Error>

        switch priority {
        case .none:
            return try await operation()
        case .inherit:
            taskPriority = nil
            taskInitializer = Task.init
        case .enforce(let priority):
            taskPriority = priority
            taskInitializer = Task.init
        case .detached(let priority):
            taskPriority = priority
            taskInitializer = Task.detached
        }

        let task = taskInitializer(taskPriority, operation)
        return try await withTaskCancellationHandler(
            handler: {
                task.cancel()
            },
            operation: {
                return try await task.value
            })
    }

    /// Executes the given operation asynchronously as a barrier based on the priority.
    ///
    /// - Parameters:
    ///   - priority: The priority with which operation executed.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    @inline(__always)
    private func runAsBarrier<T>(
        with priority: Priority,
        operation: @Sendable @escaping () async throws -> T
    ) async rethrows -> T {
        barriered = true
        do {
            let result = try await run(with: priority, operation: operation)
            await releaseBarrier()
            return result
        } catch {
            await releaseBarrier()
            throw error
        }
    }

    /// Creates a new concurrent task queue for running submitted tasks concurrently
    /// with the priority of the submitted tasks.
    ///
    /// - Parameter priority: The default priority of the tasks submitted to queue.
    ///                       By default ``Priority-swift.enum/none`` is used
    ///                       to execute tasks directly without creating as a new top-level task.
    ///
    /// - Returns: The newly created concurrent task queue.
    public init(priority: Priority = .none) {
        self.priority = priority
    }

    deinit { self.queue.forEach { $0.value.cancel() } }

    /// Executes the given throwing operation asynchronously based on the priority.
    ///
    /// Immediately runs the provided operation if queue isn't locked by barrier task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// You can set the `barrier` flag to `true` to block queue until provided operation finishes.
    /// By default, the flag is set to `false`. When opting in to run operation as barrier,
    /// only newly submitted operations will be added to queue to be executed later,
    /// while already running operations won't be affected.
    ///
    /// If a new barrier task is added while queue is locked by another barrier task,
    /// the new task will be added queue and will only block tasks that are added after it to the queue.
    ///
    /// - Parameters:
    ///   - barrier: If the task should run as a barrier blocking queue.
    ///   - priority: The priority with which operation executed.
    ///               By default ``Priority-swift.enum/none`` is used
    ///               to execute tasks directly without creating as a new top-level task.
    ///   - operation: The throwing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    /// - Throws: `CancellationError` if cancelled, or error from provided operation.
    ///
    /// - Note: If task that added the operation to queue is cancelled,
    ///         the provided operation also cancelled cooperatively if already started
    ///         or the operation execution is skipped if only queued and not started.
    @discardableResult
    public func exec<T>(
        barrier: Bool = false,
        priority: Priority? = nil,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        func runTask() async throws -> T {
            return barrier
                ? try await runAsBarrier(
                    with: priority ?? self.priority,
                    operation: operation
                )
                : try await run(
                    with: priority ?? self.priority,
                    operation: operation
                )
        }

        guard barriered || !queue.isEmpty else { return try await runTask() }
        try await withPromisedContinuation(barrier: barrier)
        return try await runTask()
    }

    /// Executes the given non-throwing operation asynchronously based on the priority.
    ///
    /// Immediately runs the provided operation if queue isn't locked by barrier task,
    /// otherwise adds operation to queue to be executed later.
    ///
    /// You can set the `barrier` flag to `true` to block queue until provided operation finishes.
    /// By default, the flag is set to `false`. When opting in to run operation as barrier,
    /// only newly submitted operations will be added to queue to be executed later,
    /// while already running operations won't be affected.
    ///
    /// If a new barrier task is added while queue is locked by another barrier task,
    /// the new task will be added queue and will only block tasks that are added after it to the queue.
    ///
    /// - Parameters:
    ///   - barrier: If the task should run as a barrier blocking queue.
    ///   - priority: The priority with which operation executed.
    ///               By default ``Priority-swift.enum/none`` is used
    ///               to execute tasks directly without creating as a new top-level task.
    ///   - operation: The non-throwing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    @discardableResult
    public func exec<T>(
        barrier: Bool = false,
        priority: Priority? = nil,
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        func runTask() async -> T {
            return barrier
                ? await runAsBarrier(
                    with: priority ?? self.priority,
                    operation: operation
                )
                : await run(
                    with: priority ?? self.priority,
                    operation: operation
                )
        }

        guard barriered || !queue.isEmpty else { return await runTask() }
        do {
            try await withPromisedContinuation(barrier: barrier)
        } catch {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return await runTask()
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
