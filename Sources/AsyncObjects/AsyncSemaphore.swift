import Foundation
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
    private typealias Continuation = GlobalContinuation<Void, Error>
    /// The continuations stored with an associated key for all the suspended task that are waitig for access to resource.
    private var continuations: OrderedDictionary<UUID, Continuation> = [:]
    /// Pool size for concurrent resource access.
    /// Has value provided during initialization incremented by one.
    private var limit: UInt
    /// Current count of semaphore.
    /// Can have maximum value upto `limit`.
    private var count: Int

    /// Add continuation with the provided key in `continuations` map.
    ///
    /// - Parameters:
    ///   - continuation: The `continuation` to add.
    ///   - key: The key in the map.
    @inline(__always)
    private func addContinuation(
        _ continuation: Continuation,
        withKey key: UUID
    ) {
        continuations[key] = continuation
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map.
    ///
    /// - Parameter key: The key in the map.
    @inline(__always)
    private func removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
        incrementCount()
    }

    /// Increments semaphore count within limit provided.
    @inline(__always)
    private func incrementCount() {
        guard count < limit else { return }
        count += 1
    }

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
    @Sendable
    public func signal() {
        incrementCount()
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
        if count > 0 { return }
        let key = UUID()
        try? await withThrowingContinuationCancellationHandler(
            handler: { [weak self] continuation in
                Task { [weak self] in
                    await self?.removeContinuation(withKey: key)
                }
            },
            { [weak self] continuation in
                Task { [weak self] in
                    await self?.addContinuation(continuation, withKey: key)
                }
            }
        )
    }
}
