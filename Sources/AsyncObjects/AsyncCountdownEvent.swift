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
/// or its timeout variation ``wait(forNanoseconds:)``.
///
/// Use the ``limit`` parameter to indicate concurrent low priority usage, i.e. if limit set to zero,
/// only one low priority usage allowed at one time.
public actor AsyncCountdownEvent: AsyncObject {
    /// The suspended tasks continuation type.
    @usableFromInline
    typealias Continuation = GlobalContinuation<Void, Error>
    /// The continuations stored with an associated key for all the suspended task that are waiting to be resumed.
    @usableFromInline
    private(set) var continuations: OrderedDictionary<UUID, Continuation> = [:]
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
    public private(set) var initialCount: UInt
    /// Indicates whether countdown event current count is within ``limit``.
    ///
    /// Queued tasks are resumed from suspension when event is set and until current count exceeds limit.
    public var isSet: Bool { currentCount >= 0 && currentCount <= limit }

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
        guard !isSet, continuations.isEmpty else {
            currentCount += 1
            continuation.resume()
            return
        }
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
    }

    /// Decrements countdown count by the provided number.
    ///
    /// - Parameter number: The number to decrement count by.
    @inlinable
    func _decrementCount(by number: UInt = 1) {
        defer { _resumeContinuations() }
        guard currentCount > 0 else { return }
        currentCount -= number
    }

    /// Resume previously waiting continuations for countdown event.
    @inlinable
    func _resumeContinuations() {
        while !continuations.isEmpty && isSet {
            let (_, continuation) = continuations.removeFirst()
            continuation.resume()
            self.currentCount += 1
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
    public func increment(by count: UInt = 1) {
        self.currentCount += count
    }

    /// Resets current count to initial count.
    ///
    /// If the current count becomes less or equal to limit, multiple queued tasks
    /// are resumed from suspension until current count exceeds limit.
    public func reset() {
        self.currentCount = initialCount
        _resumeContinuations()
    }

    /// Resets initial count and current count to specified value.
    ///
    /// If the current count becomes less or equal to limit, multiple queued tasks
    /// are resumed from suspension until current count exceeds limit.
    ///
    /// - Parameter count: The new initial count.
    public func reset(to count: UInt) {
        initialCount = count
        self.currentCount = count
        _resumeContinuations()
    }

    /// Registers a signal (decrements) with the countdown event.
    ///
    /// Decrement the countdown. If the current count becomes less or equal to limit,
    /// one queued task is resumed from suspension.
    public func signal() {
        signal(repeat: 1)
    }

    /// Registers multiple signals (decrements by provided count) with the countdown event.
    ///
    /// Decrement the countdown by the provided count. If the current count becomes less or equal to limit,
    /// multiple queued tasks are resumed from suspension until current count exceeds limit.
    ///
    /// - Parameter count: The number of signals to register.
    public func signal(repeat count: UInt) {
        _decrementCount(by: count)
    }

    /// Waits for, or increments, a countdown event.
    ///
    /// Increment the countdown if the current count is less or equal to limit.
    /// Otherwise, current task is suspended until either a signal occurs or event is reset.
    ///
    /// Use this to wait for high priority tasks completion to start low priority ones.
    @Sendable
    public func wait() async {
        guard !isSet else { currentCount += 1; return }
        try? await _withPromisedContinuation()
    }
}
