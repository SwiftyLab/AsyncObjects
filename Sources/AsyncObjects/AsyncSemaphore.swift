@preconcurrency import Foundation
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
public actor AsyncSemaphore: AsyncObject, ContinuableCollection {
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
    ) {
        Task { await _signal() }
    }

    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than zero,
    /// current task is suspended until a signal occurs.
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
        guard count <= 1 else { count -= 1; return }
        try await _withPromisedContinuation()
    }
}
