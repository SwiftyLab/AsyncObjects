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
/// You can indicate high priority usage of resource by using ``increment(by:file:function:line:)``
/// method, and indicate free of resource by calling ``signal(repeat:file:function:line:)``
/// or ``signal(file:function:line:)`` methods.
/// For low priority resource usage or detect resource idling use ``wait(file:function:line:)``
/// method or its timeout variation ``wait(until:tolerance:clock:file:function:line:)``:
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
public actor AsyncCountdownEvent: AsyncObject, ContinuableCollection,
    LoggableActor
{
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = TrackedContinuation<
        GlobalContinuation<Void, Error>
    >

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
    /// Can be changed after initialization by using
    /// ``reset(to:file:function:line:)``
    /// method.
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
    internal func shouldWait() -> Bool { !isSet || !continuations.isEmpty }

    /// Resume provided continuation with additional changes based on the associated flags.
    ///
    /// - Parameter continuation: The queued continuation to resume.
    @inlinable
    internal func resumeContinuation(_ continuation: Continuation) {
        currentCount += 1
        continuation.resume()
    }

    /// Add continuation with the provided key in `continuations` map.
    ///
    /// - Parameters:
    ///   - continuation: The `continuation` to add.
    ///   - key: The key in the map.
    ///   - file: The file add request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function add request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line add request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - preinit: The pre-initialization handler to run
    ///              in the beginning of this method.
    ///
    /// - Important: The pre-initialization handler must run
    ///              before any logic in this method.
    @inlinable
    internal func addContinuation(
        _ continuation: Continuation,
        withKey key: UUID,
        file: String, function: String, line: UInt,
        preinit: @escaping @Sendable () -> Void
    ) {
        preinit()
        log("Adding", id: key, file: file, function: function, line: line)
        guard !continuation.resumed else {
            log(
                "Already resumed, not tracking", id: key,
                file: file, function: function, line: line
            )
            return
        }

        guard shouldWait() else {
            resumeContinuation(continuation)
            log("Resumed", id: key, file: file, function: function, line: line)
            return
        }

        continuations[key] = continuation
        log("Tracking", id: key, file: file, function: function, line: line)
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameters:
    ///   - continuation: The continuation to remove and cancel.
    ///   - key: The key in the map.
    ///   - file: The file remove request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function remove request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line remove request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func removeContinuation(
        _ continuation: Continuation,
        withKey key: UUID,
        file: String, function: String, line: UInt
    ) {
        log("Removing", id: key, file: file, function: function, line: line)
        continuations.removeValue(forKey: key)
        guard !continuation.resumed else {
            log(
                "Already resumed, not cancelling", id: key,
                file: file, function: function, line: line
            )
            return
        }

        continuation.cancel()
        log("Cancelled", id: key, file: file, function: function, line: line)
    }

    /// Decrements countdown count by the provided number.
    ///
    /// - Parameters:
    ///   - number: The number to decrement count by.
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func decrementCount(
        by number: UInt = 1,
        file: String, function: String, line: UInt
    ) {
        defer {
            resumeContinuations(file: file, function: function, line: line)
        }

        guard currentCount > 0 else {
            log("Least count", file: file, function: function, line: line)
            return
        }

        currentCount -= number
        log("Decremented", file: file, function: function, line: line)
    }

    /// Resume previously waiting continuations for countdown event.
    ///
    /// - Parameters:
    ///   - file: The file resume originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function resume originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line resume originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func resumeContinuations(
        file: String, function: String, line: UInt
    ) {
        while !continuations.isEmpty && isSet {
            let (key, continuation) = continuations.removeFirst()
            resumeContinuation(continuation)
            log("Resumed", id: key, file: file, function: function, line: line)
        }
    }

    /// Increments the countdown event current count by the specified value.
    ///
    /// - Parameters:
    ///   - count: The value by which to increase ``currentCount``.
    ///   - file: The file increment originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function increment originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line increment originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func incrementCount(
        by count: UInt = 1,
        file: String, function: String, line: UInt
    ) {
        self.currentCount += count
        log("Incremented", file: file, function: function, line: line)
    }

    /// Resets initial count and current count to specified value.
    ///
    /// - Parameters:
    ///   - count: The new initial count.
    ///   - file: The file reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function reset originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func resetCount(
        to count: UInt?,
        file: String, function: String, line: UInt
    ) {
        defer {
            resumeContinuations(file: file, function: function, line: line)
        }

        let count = count ?? initialCount
        initialCount = count
        self.currentCount = count
        log("Reset", file: file, function: function, line: line)
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

    deinit {
        log("Deinitialized")
        self.continuations.forEach { $1.cancel() }
    }

    /// Increments the countdown event current count by the specified value.
    ///
    /// Unlike the ``wait(file:function:line:)`` method
    /// count is reflected immediately. Use this to indicate usage of
    /// resource from high priority tasks.
    ///
    /// - Parameters:
    ///   - count: The value by which to increase ``currentCount``.
    ///   - file: The file increment originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function increment originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line increment originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    public nonisolated func increment(
        by count: UInt = 1,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            await incrementCount(
                by: count,
                file: file, function: function, line: line
            )
        }
    }

    /// Resets initial count and current count to specified value.
    ///
    /// If the current count becomes less or equal to limit, multiple queued tasks
    /// are resumed from suspension until current count exceeds limit.
    ///
    /// - Parameters:
    ///   - count: The new initial count.
    ///   - file: The file reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function reset originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    public nonisolated func reset(
        to count: UInt? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            await resetCount(
                to: count,
                file: file, function: function, line: line
            )
        }
    }

    /// Registers a signal (decrements) with the countdown event.
    ///
    /// Decrement the countdown. If the current count becomes less or equal to limit,
    /// one queued task is resumed from suspension.
    ///
    /// - Parameters:
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    public nonisolated func signal(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            await decrementCount(
                by: 1,
                file: file, function: function, line: line
            )
        }
    }

    /// Registers multiple signals (decrements by provided count) with the countdown event.
    ///
    /// Decrement the countdown by the provided count. If the current count becomes less or equal to limit,
    /// multiple queued tasks are resumed from suspension until current count exceeds limit.
    ///
    /// - Parameters:
    ///   - count: The number of signals to register.
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    public nonisolated func signal(
        repeat count: UInt,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            await decrementCount(
                by: count,
                file: file, function: function, line: line
            )
        }
    }

    /// Waits for, or increments, a countdown event.
    ///
    /// Increment the countdown if the current count is less or equal to limit.
    /// Otherwise, current task is suspended until either a signal occurs or event is reset.
    ///
    /// Use this to wait for high priority tasks completion to start low priority ones.
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
        guard shouldWait() else {
            currentCount += 1
            log("Acquired", file: file, function: function, line: line)
            return
        }

        let key = UUID()
        log("Waiting", id: key, file: file, function: function, line: line)
        try await withPromisedContinuation(
            withKey: key,
            file: file, function: function, line: line
        )
        log("Received", id: key, file: file, function: function, line: line)
    }
}

#if canImport(Logging)
import Logging

extension AsyncCountdownEvent {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)(\(Unmanaged.passUnretained(self).toOpaque()))",
            "limit": "\(limit)",
            "current_count": "\(currentCount)",
            "initial_count": "\(initialCount)",
        ]
    }
}
#endif
