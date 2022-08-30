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
/// or its timeout variation ``wait(forNanoseconds:)``.
public actor AsyncSemaphore: AsyncObject {
    /// The suspended tasks continuation type.
    @usableFromInline
    typealias Continuation = GlobalContinuation<Void, Error>
    /// The continuations stored with an associated key for all the suspended task that are waiting for access to resource.
    @usableFromInline
    private(set) var continuations: OrderedDictionary<UUID, Continuation> = [:]
    /// Pool size for concurrent resource access.
    /// Has value provided during initialization incremented by one.
    @usableFromInline
    private(set) var limit: UInt
    /// Current count of semaphore.
    /// Can have maximum value up to `limit`.
    @usableFromInline
    private(set) var count: Int

    // MARK: Internal

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
        guard count <= 0 else { continuation.resume(); return }
        continuations[key] = continuation
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    func _removeContinuation(withKey key: UUID) {
        let continuation = continuations.removeValue(forKey: key)
        continuation?.cancel()
        _incrementCount()
    }

    /// Increments semaphore count within limit provided.
    @inlinable
    func _incrementCount() {
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
    nonisolated func _withPromisedContinuation() async throws {
        let key = UUID()
        try await withTaskCancellationHandler { [weak self] in
            Task { [weak self] in
                await self?._removeContinuation(withKey: key)
            }
        } operation: { () -> Continuation.Success in
            try await Continuation.with { continuation in
                Task { [weak self] in
                    await self?._addContinuation(continuation, withKey: key)
                }
            }
        }
    }

    // MARK: Public

    /// Creates new counting semaphore with an initial value.
    /// By default, initial value is zero.
    ///
    /// Passing zero for the value is useful for when two threads need to reconcile the completion of a particular event.
    /// Passing a value greater than zero is useful for managing a finite pool of resources, where the pool size is equal to the value.
    ///
    /// - Parameter count: The starting value for the semaphore.
    ///
    /// - Returns: The newly created semaphore.
    public init(value count: UInt = 0) {
        self.limit = count + 1
        self.count = Int(limit)
    }

    deinit { self.continuations.forEach { $0.value.cancel() } }

    /// Signals (increments) a semaphore.
    ///
    /// Increment the counting semaphore.
    /// If the previous value was less than zero,
    /// current task is resumed from suspension.
    public func signal() {
        _incrementCount()
        guard !continuations.isEmpty else { return }
        let (_, continuation) = continuations.removeFirst()
        continuation.resume()
    }

    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than zero,
    /// current task is suspended until a signal occurs.
    @Sendable
    public func wait() async {
        count -= 1
        guard count <= 0 else { return }
        try? await _withPromisedContinuation()
    }
}
