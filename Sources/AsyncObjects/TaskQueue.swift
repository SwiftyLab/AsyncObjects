import Foundation
import OrderedCollections

/// An object that acts as a concurrent queue executing submitted tasks concurrently.
///
/// You can use the ``exec(barrier:priority:task:)-3a9s9`` or its nonthrowing version
/// to run tasks concurrently. Optionally, you can enable the `barrier` flag for submitted task to block the queue until the provided task
/// completes execution.
public actor TaskQueue: AsyncObject {
    /// A mechanism to queue tasks in ``TaskQueue`` as a concurrent task or as a barrier task,
    /// to be resumed when queue is freed from existing barrier task.
    fileprivate struct QueuedContinuation {
        /// Whether continuation is associated with any barrier task.
        fileprivate let barrier: Bool
        /// The queued continuation to be resumed later.
        fileprivate let continuation: SafeContinuation<Void, Error>

        /// Creates a new continuation for task queued in ``TaskQueue``.
        ///
        /// - Parameters:
        ///   - barrier: If the continuation is associated with any barrier task.
        ///   - continuation: The continuation to be resumed on turn.
        ///
        /// - Returns: The newly created queued continuation.
        fileprivate init(
            barrier: Bool = false,
            continuation: SafeContinuation<Void, Error>
        ) {
            self.barrier = barrier
            self.continuation = continuation
        }

        /// Resume the provided continuation if not done already.
        ///
        /// Multiple invocations are ignored and only first invocation accepted.
        fileprivate func resume() { continuation.resume() }
    }

    /// The suspended tasks continuation type.
    private typealias Continuation = SafeContinuation<Void, Error>
    /// The list of tasks currently queued and would be resumed one by one when current barrier task ends.
    private var queue: OrderedDictionary<UUID, QueuedContinuation> = [:]
    /// Indicates whether queue is locked by a barrier task currently running.
    internal private(set) var barriered: Bool = false
    /// The default priority with which new tasks on the queue are started.
    ///
    /// TODO: Implement priority based task invocations.
    private let priority: TaskPriority?

    /// Add continuation (both throwing and nonthrowing) with the provided key in queue.
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
        queue.removeValue(forKey: key)
    }

    /// Release barrier allowing other queued tasks to run
    /// after barrier task completes successfully or cancelled.
    ///
    /// Updates the barrier flag and starts queued tasks
    /// in order of their addition if any tasks are queued.
    @inline(__always)
    private func releaseBarrier() async {
        barriered = false
        while true {
            guard !queue.isEmpty else { break }
            let (_, continuation) = queue.removeFirst()
            continuation.resume()
            if continuation.barrier { break }
        }
    }

    /// Creates a new concurrent task queue for running submitted tasks concurrently
    /// with the priority of the submitted tasks.
    ///
    /// - Parameter priority: The priority of the tasks submitted to queue.
    ///                       Pass nil to use the priority from `Task.currentPriority`.
    ///
    /// - Returns: The newly created cocurrent task queue.
    public init(priority: TaskPriority? = nil) {
        self.priority = priority
    }

    /// Executes the given throwing operation asynchronously.
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
    ///   - priority: The priority of the task.
    ///               Pass nil to use the priority from `Task.currentPriority`.
    ///   - task: The throwing operation to perform.
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
        priority: TaskPriority? = nil,
        task: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        func runTaskAsBarrier() async throws -> T {
            barriered = true
            let result = try await task()
            await releaseBarrier()
            return result
        }

        guard barriered || !queue.isEmpty else {
            if !barrier { return try await task() }
            do {
                return try await runTaskAsBarrier()
            } catch {
                await releaseBarrier()
                throw error
            }
        }

        let key = UUID()
        do {
            try await withThrowingContinuationCancellationHandler(
                handler: { [weak self] continuation in
                    Task { [weak self] in
                        await self?.dequeueContinuation(withKey: key)
                    }
                },
                { continuation in
                    queueContinuation(
                        barrier: barrier, atKey: key, continuation)
                }
            )
            return barrier ? try await runTaskAsBarrier() : try await task()
        } catch {
            if barrier { await releaseBarrier() }
            throw error
        }
    }

    /// Executes the given nonthrowing operation asynchronously.
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
    ///   - priority: The priority of the task.
    ///               Pass nil to use the priority from `Task.currentPriority`.
    ///   - task: The nonthrowing operation to perform.
    ///
    /// - Returns: The result from provided operation.
    @discardableResult
    public func exec<T>(
        barrier: Bool = false,
        priority: TaskPriority? = nil,
        task: @Sendable @escaping () async -> T
    ) async -> T {
        func runTaskAsBarrier() async -> T {
            barriered = true
            let result = await task()
            await releaseBarrier()
            return result
        }

        func runTask() async -> T {
            return barrier ? await runTaskAsBarrier() : await task()
        }

        guard barriered || !queue.isEmpty else { return await runTask() }
        let key = UUID()
        do {
            try await withThrowingContinuationCancellationHandler(
                handler: { [weak self] continuation in
                    Task { [weak self] in
                        await self?.dequeueContinuation(withKey: key)
                    }
                },
                { continuation in
                    queueContinuation(
                        barrier: barrier, atKey: key, continuation)
                }
            )
        } catch {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return await runTask()
    }

    /// Signalling on queue does nothing.
    /// Only added to satisfy ``AsyncObject`` reuirements.
    public func signal() async {
        // Do nothing
    }

    /// Waits for execution turn on queue.
    ///
    /// Only waits asynchronously, if queue is locked by a barrier task,
    /// until the suspended task's turn comes to be resumed.
    public func wait() async {
        await exec { /*Do nothing*/  }
    }
}

/// A mechanism to interface between synchronous and asynchronous code,
/// ignoring correctness violations.
///
/// A continuation is an opaque representation of program state.
/// Resuming from standard library continuations more than once is undefined behavior and causes runtime error,
/// while `SafeContinuation` only resumes once and subsequent resuming are ignored and has no effect.
/// Never resuming leaves the task in a suspended state indefinitely, and leaks any associated resources.
/// `SafeContinuation` doesn't notify if this invariant is violated.
struct SafeContinuation<T: Sendable, E: Error>: Continuable {
    /// A reference type wrabber for boolean value.
    private final class Flag: Sendable {
        /// The state of the flag, on state represented by `true`
        /// while off represented by `false`.
        fileprivate private(set) var value: Bool = true

        /// Turn on the flag by changing `value` to `true`.
        fileprivate func on() { value = true }
        /// Turn off the flag by changing `value` to `false`.
        fileprivate func off() { value = false }
    }

    /// The underlying continuation used.
    private let wrappedValue: GlobalContinuation<T, E>
    /// Keeps track whether continuation can be resumed,
    /// to make sure continuation only resumes once.
    private let resumable: Flag = {
        let flag = Flag()
        flag.on()
        return flag
    }()

    /// Creates a safe continuation from provided continuation.
    ///
    /// - Parameter continuation: A continuation that hasn’t yet been resumed.
    ///                           After passing the continuation to this initializer,
    ///                           don’t use it outside of this object.
    ///
    /// - Returns: The newly created safe continuation.
    init(continuation: GlobalContinuation<T, E>) {
        self.wrappedValue = continuation
    }

    /// Resume the task awaiting the continuation by having it return normally from its suspension point.
    ///
    /// Continuation is resumed exactly once.
    /// If the continuation has already been resumed through this object,
    /// then the attempt to resume the continuation will have no effect.
    /// After resume enqueues the task, control immediately returns to the caller.
    /// The task continues executing when its executor is able to reschedule it.
    func resume() where T == Void {
        resume(returning: ())
    }

    /// Resume the task awaiting the continuation by having it return normally from its suspension point.
    ///
    /// Continuation is resumed exactly once.
    /// If the continuation has already been resumed through this object,
    /// then the attempt to resume the continuation will have no effect.
    /// After resume enqueues the task, control immediately returns to the caller.
    /// The task continues executing when its executor is able to reschedule it.
    ///
    /// - Parameter value: The value to return from the continuation.
    func resume(returning value: T) {
        guard resumable.value else { return }
        wrappedValue.resume(returning: value)
        resumable.off()
    }

    /// Resume the task awaiting the continuation by having it throw an error from its suspension point.
    ///
    /// Continuation is resumed exactly once.
    /// If the continuation has already been resumed through this object,
    /// then the attempt to resume the continuation will have no effect.
    /// After resume enqueues the task, control immediately returns to the caller.
    /// The task continues executing when its executor is able to reschedule it.
    ///
    /// - Parameter error: The error to throw from the continuation.
    func resume(throwing error: E) {
        guard resumable.value else { return }
        wrappedValue.resume(throwing: error)
        resumable.off()
    }

    /// Resume the task awaiting the continuation by having it either return normally
    /// or throw an error based on the state of the given `Result` value.
    ///
    /// Continuation is resumed exactly once.
    /// If the continuation has already been resumed through this object,
    /// then the attempt to resume the continuation will have no effect.
    /// After resume enqueues the task, control immediately returns to the caller.
    /// The task continues executing when its executor is able to reschedule it.
    ///
    /// - Parameter result: A value to either return or throw from the continuation.
    func resume(with result: Result<T, E>) {
        guard resumable.value else { return }
        wrappedValue.resume(with: result)
        resumable.off()
    }
}

extension SafeContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with a safe throwing continuation for the current task.
    ///
    /// The continuation can be resumed exactly once, subsequent resumes are ignored.
    ///
    /// - Parameter fn: A closure that takes the throwing continuation parameter.
    ///                 You can resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    static func with(_ fn: (SafeContinuation<T, E>) -> Void) async throws -> T {
        return try await GlobalContinuation<T, E>.with { continuation in
            fn(.init(continuation: continuation))
        }
    }
}
