#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif
import OrderedCollections

/// An event object that controls access to a resource between high and low priority tasks
/// and signals when count is within limit.
///
/// An async countdown event is an inverse of ``AsyncSemaphore``,
/// in the sense that instead of restricting access to a resource,
/// it notifies when the resource usage is idle or inefficient.
///
/// You can indicate high priority usage of resource by using ``increment(by:)`` method,
/// and indicate free of resource by calling ``signal(repeat:)`` or ``signal()`` methods.
/// For low priority resource usage or detect resource idling use ``wait()`` method
/// or its timeout variation ``wait(forNanoseconds:)``:
///
/// ```swift
/// // create event with initial count and count down limit
/// let event = AsyncCountdownEvent()
/// // increment countdown count from high priority tasks
/// event.increment(by: 1)
///
/// // wait for countdown signal from low priority tasks,
/// // fails only if task cancelled
/// try await event.wait()
/// // or wait with some timeout
/// try await event.wait(forNanoseconds: 1_000_000_000)
///
/// // signal countdown after completing high priority tasks
/// event.signal()
/// ```
///
/// Use the ``limit`` parameter to indicate concurrent low priority usage, i.e. if limit set to zero,
/// only one low priority usage allowed at one time.
public actor AsyncCountdownEvent: AsyncObject, ContinuableCollection {
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = SafeContinuation<
        GlobalContinuation<Void, Error>
    >
    /// The platform dependent lock used to synchronize continuations tracking.
    @usableFromInline
    internal let locker: Locker = .init()
    /// The continuations stored with an associated key for all the suspended task that are waiting to be resumed.
    @usableFromInline
    internal private(set) var continuations:
        OrderedDictionary<
            UUID,
            Continuation
        > = [:]
    /// The limit up to which the countdown counts and triggers event.
    ///
    /// By default this is set to zero and can be changed during initialization.
    public let limit: UInt
    /// Current count of the countdown.
    ///
    /// If the current count becomes less or equal to limit, queued tasks
    /// are resumed from suspension until current count exceeds limit.
    public var currentCount: UInt
    /// Initial count of the countdown when count started.
    ///
    /// Can be changed after initialization
    /// by using ``reset(to:)`` method.
    public var initialCount: UInt
    /// Indicates whether countdown event current count is within ``limit``.
    ///
    /// Queued tasks are resumed from suspension when event is set and until current count exceeds limit.
    public var isSet: Bool { currentCount >= 0 && currentCount <= limit }

    // MARK: Internal

    /// Checks whether to wait for countdown to signal.
    ///
    /// - Returns: Whether to wait to be resumed later.
    @inlinable
    internal func _wait() -> Bool { !isSet || !continuations.isEmpty }

    /// Resume provided continuation with additional changes based on the associated flags.
    ///
    /// - Parameter continuation: The queued continuation to resume.
    @inlinable
    internal func _resumeContinuation(_ continuation: Continuation) {
        currentCount += 1
        continuation.resume()
    }

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
        guard !continuation.resumed else { return }
        guard _wait() else { _resumeContinuation(continuation); return }
        continuations[key] = continuation
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    internal func _removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
    }

    /// Decrements countdown count by the provided number.
    ///
    /// - Parameter number: The number to decrement count by.
    @inlinable
    internal func _decrementCount(by number: UInt = 1) {
        defer { _resumeContinuations() }
        guard currentCount > 0 else { return }
        currentCount -= number
    }

    /// Resume previously waiting continuations for countdown event.
    @inlinable
    internal func _resumeContinuations() {
        while !continuations.isEmpty && isSet {
            let (_, continuation) = continuations.removeFirst()
            _resumeContinuation(continuation)
        }
    }

    /// Increments the countdown event current count by the specified value.
    ///
    /// - Parameter count: The value by which to increase ``currentCount``.
    @inlinable
    internal func _increment(by count: UInt = 1) {
        self.currentCount += count
    }

    /// Resets current count to initial count.
    @inlinable
    internal func _reset() {
        self.currentCount = initialCount
        _resumeContinuations()
    }

    /// Resets initial count and current count to specified value.
    ///
    /// - Parameter count: The new initial count.
    @inlinable
    internal func _reset(to count: UInt) {
        initialCount = count
        self.currentCount = count
        _resumeContinuations()
    }

    // MARK: Public

    /// Creates new countdown event with the limit count down up to and an initial count.
    /// By default, both limit and initial count are zero.
    ///
    /// Passing zero for the limit value is useful for when one low priority access should be given
    /// in absence of high priority resource usages. Passing a value greater than zero for the limit is useful
    /// for managing a finite limit of access to low priority tasks, in absence of high priority resource usages.
    ///
    /// - Parameters:
    ///   - limit: The value to count down up to.
    ///   - initial: The initial count.
    ///
    /// - Returns: The newly created countdown event .
    public init(until limit: UInt = 0, initial: UInt = 0) {
        self.limit = limit
        self.initialCount = initial
        self.currentCount = initial
    }

    deinit { self.continuations.forEach { $0.value.cancel() } }

    /// Increments the countdown event current count by the specified value.
    ///
    /// Unlike the ``wait()`` method count is reflected immediately.
    /// Use this to indicate usage of resource from high priority tasks.
    ///
    /// - Parameter count: The value by which to increase ``currentCount``.
    public nonisolated func increment(by count: UInt = 1) {
        Task { await _increment(by: count) }
    }

    /// Resets current count to initial count.
    ///
    /// If the current count becomes less or equal to limit, multiple queued tasks
    /// are resumed from suspension until current count exceeds limit.
    public nonisolated func reset() {
        Task { await _reset() }
    }

    /// Resets initial count and current count to specified value.
    ///
    /// If the current count becomes less or equal to limit, multiple queued tasks
    /// are resumed from suspension until current count exceeds limit.
    ///
    /// - Parameter count: The new initial count.
    public nonisolated func reset(to count: UInt) {
        Task { await _reset(to: count) }
    }

    /// Registers a signal (decrements) with the countdown event.
    ///
    /// Decrement the countdown. If the current count becomes less or equal to limit,
    /// one queued task is resumed from suspension.
    public nonisolated func signal() {
        Task { await _decrementCount(by: 1) }
    }

    /// Registers multiple signals (decrements by provided count) with the countdown event.
    ///
    /// Decrement the countdown by the provided count. If the current count becomes less or equal to limit,
    /// multiple queued tasks are resumed from suspension until current count exceeds limit.
    ///
    /// - Parameter count: The number of signals to register.
    public nonisolated func signal(repeat count: UInt) {
        Task { await _decrementCount(by: count) }
    }

    /// Waits for, or increments, a countdown event.
    ///
    /// Increment the countdown if the current count is less or equal to limit.
    /// Otherwise, current task is suspended until either a signal occurs or event is reset.
    ///
    /// Use this to wait for high priority tasks completion to start low priority ones.
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func wait() async throws {
        guard _wait() else { currentCount += 1; return }
        try await _withPromisedContinuation()
    }
}
