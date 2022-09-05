#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif
import OrderedCollections

/// An object that controls access to a resource across multiple task contexts through use of a traditional counting semaphore.
///
/// An async semaphore is an efficient implementation of a traditional counting semaphore.
/// Unlike traditional semaphore, async semaphore suspends current task instead of blocking threads.
///
/// You increment a semaphore count by calling the ``signal()`` method
/// and decrement a semaphore count by calling ``wait()`` method
/// or its timeout variation ``wait(forNanoseconds:)``:
///
/// ```swift
/// // create limiting concurrent access count
/// let semaphore = AsyncSemaphore(value: 1)
/// // wait for semaphore access,
/// // fails only if task cancelled
/// try await semaphore.wait()
/// // or wait with some timeout
/// try await semaphore.wait(forNanoseconds: 1_000_000_000)
/// // release after executing critical async tasks
/// defer { semaphore.signal() }
/// ```
public actor AsyncSemaphore: AsyncObject {
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = SafeContinuation<
        GlobalContinuation<Void, Error>
    >
    /// The platform dependent lock used to synchronize continuations tracking.
    @usableFromInline
    internal let locker: Locker = .init()
    /// The continuations stored with an associated key for all the suspended task that are waiting for access to resource.
    @usableFromInline
    internal private(set) var continuations:
        OrderedDictionary<
            UUID,
            Continuation
        > = [:]
    /// Pool size for concurrent resource access.
    /// Has value provided during initialization incremented by one.
    @usableFromInline
    internal let limit: UInt
    /// Current count of semaphore.
    /// Can have maximum value up to `limit`.
    @usableFromInline
    internal private(set) var count: Int

    // MARK: Internal

    /// Add continuation with the provided key in `continuations` map.
    ///
    /// - Parameters:
    ///   - continuation: The `continuation` to add.
    ///   - key: The key in the map.
    @inlinable
    internal func _addContinuation(
        _ continuation: Continuation,
        withKey key: UUID
    ) {
        count -= 1
        guard !continuation.resumed else { return }
        guard count <= 0 else { continuation.resume(); return }
        continuations[key] = continuation
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    internal func _removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
        _incrementCount()
    }

    /// Increments semaphore count within limit provided.
    @inlinable
    internal func _incrementCount() {
        guard count < limit else { return }
        count += 1
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
    internal nonisolated func _withPromisedContinuation() async throws {
        let key = UUID()
        try await Continuation.withCancellation(synchronizedWith: locker) {
            Task { [weak self] in
                await self?._removeContinuation(withKey: key)
            }
        } operation: { continuation in
            Task { [weak self] in
                await self?._addContinuation(continuation, withKey: key)
            }
        }
    }

    /// Signals (increments) and releases a semaphore.
    @inlinable
    internal func _signal() {
        _incrementCount()
        guard !continuations.isEmpty else { return }
        let (_, continuation) = continuations.removeFirst()
        continuation.resume()
    }

    // MARK: Public

    /// Creates new counting semaphore with an initial value.
    /// By default, initial value is zero.
    ///
    /// Passing zero for the value is useful for when two threads need to reconcile the completion of a particular event.
    /// Passing a value greater than zero is useful for managing a finite pool of resources, where the pool size is equal to the value.
    ///
    /// - Parameter count: The starting value for the semaphore.
    /// - Returns: The newly created semaphore.
    public init(value count: UInt = 0) {
        self.limit = count + 1
        self.count = Int(limit)
    }

    deinit { self.continuations.forEach { $0.value.cancel() } }

    /// Signals (increments) a semaphore.
    ///
    /// Increment the counting semaphore.
    /// If any previous task is waiting for access to semaphore,
    /// then the task is resumed from suspension.
    @Sendable
    public nonisolated func signal() {
        Task { await _signal() }
    }

    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than zero,
    /// current task is suspended until a signal occurs.
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func wait() async throws {
        guard count <= 1 else { count -= 1; return }
        try await _withPromisedContinuation()
    }
}
