import Foundation
import AsyncAlgorithms

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
public final class AsyncCountdownEvent: AsyncObject, Loggable, @unchecked
    Sendable
{
    /// A  type representing various mutation actions that
    /// can be performed on `AsyncCountdownEvent`.
    @usableFromInline
    internal enum Action: Sendable {
        /// An action representing decrement of
        /// current count in `AsyncCountdownEvent`.
        ///
        /// The current count is decremented by the provided count
        /// or set to zero if provided count is greater.
        case decrement(by: UInt)
        /// An action representing increment of
        /// current count in `AsyncCountdownEvent`.
        ///
        /// The current count is incremented by the provided count.
        case increment(by: UInt)
        /// An action representing reset of current count
        /// and initial count in `AsyncCountdownEvent`.
        ///
        /// The current count and initial count are reset to the provided count.
        /// If count not provided, current count is reset to initial count.
        case reset(to: UInt? = nil)
    }

    /// The action performed on `AsyncCountdownEvent` context type.
    @usableFromInline
    typealias ActionItem = (Action, UUID?, String, String, UInt)
    /// The wait for `AsyncCountdownEvent` set context type.
    typealias WaitItem = (UUID, String, String, UInt)

    /// The limit up to which the countdown counts and triggers event.
    ///
    /// By default this is set to zero and can be changed during initialization.
    public let limit: UInt
    /// Current count of the countdown.
    ///
    /// If the current count becomes less or equal to limit, queued tasks
    /// are resumed from suspension until current count exceeds limit.
    public private(set) var currentCount: UInt
    /// Initial count of the countdown when count started.
    ///
    /// Can be changed after initialization by using
    /// ``reset(to:file:function:line:)``
    /// method.
    public private(set) var initialCount: UInt
    /// Indicates whether countdown event current count is within ``limit``.
    ///
    /// Queued tasks are resumed from suspension when event is set and until current count exceeds limit.
    public var isSet: Bool { currentCount <= limit }

    /// The stream continuation that updates state change
    /// info for `AsyncCountdownEvent`.
    @usableFromInline
    let actor: AsyncStream<ActionItem>.Continuation
    /// The channel that controls waiting on the `AsyncCountdownEvent`.
    ///
    /// The waiting completes when `AsyncCountdownEvent` is set.
    let waiter: AsyncChannel<WaitItem>

    // MARK: Internal

    /// Updates count state according to provided action and
    /// returns whether current count is within limit.
    ///
    /// - Parameters:
    ///   - item: The action context to perform to update state.
    ///
    /// - Returns: Whether current count is within limit.
    func update(with item: ActionItem) -> Bool {
        let (action, id, file, fn, line) = item
        switch action {
        case .decrement(by: let count):
            currentCount = (currentCount >= count) ? (currentCount - count) : 0
            log("Decremented", id: id, file: file, function: fn, line: line)
        case .increment(by: let count):
            currentCount += count
            log("Incremented", id: id, file: file, function: fn, line: line)
        case .reset(to: .some(let count)):
            initialCount = count
            fallthrough
        case .reset(to: .none):
            currentCount = initialCount
            log("Reset", id: id, file: file, function: fn, line: line)
        }
        return isSet
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
    ///   - file: The file where initialization occurs (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function where initialization occurs (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line where initialization occurs (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created countdown event .
    public init(
        until limit: UInt = 0,
        initial: UInt = 0,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.limit = limit
        self.initialCount = initial
        self.currentCount = initial

        let channel = AsyncChannel<WaitItem>()
        var continuation: AsyncStream<ActionItem>.Continuation!
        let actions = AsyncStream<ActionItem> { continuation = $0 }
        let actor = continuation!
        self.actor = actor
        self.waiter = channel
        actor.yield((.reset(), nil, file, function, line))

        Task.detached { [weak self] in
            func spin() -> (Task<Void, Never>, AsyncStream<Void>.Continuation) {
                var continuation: AsyncStream<Void>.Continuation!
                let store = AsyncStream<Void>(
                    bufferingPolicy: .bufferingNewest(1)
                ) { continuation = $0 }
                let task = Task.detached {
                    signal: for await _ in store {
                        for await (id, file, fn, line) in channel {
                            actor.yield((.increment(by: 1), id, file, fn, line))
                            continue signal
                        }
                    }
                }
                return (task, continuation)
            }

            var (wt, signaller) = spin()
            defer { signaller.finish(); wt.cancel() }
            for await item in actions {
                guard let result = self?.update(with: item) else { break }
                if result {
                    signaller.yield(())
                } else {
                    signaller.finish()
                    wt.cancel()
                    (wt, signaller) = spin()
                }
            }
        }
    }

    deinit {
        actor.finish()
        waiter.finish()
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
    @inlinable
    @Sendable
    public func increment(
        by count: UInt = 1,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { actor.yield((.increment(by: count), nil, file, function, line)) }

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
    @inlinable
    @Sendable
    public func reset(
        to count: UInt? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { actor.yield((.reset(to: count), nil, file, function, line)) }

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
    @inlinable
    @Sendable
    public func signal(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { self.signal(repeat: 1, file: file, function: function, line: line) }

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
    @inlinable
    @Sendable
    public func signal(
        repeat count: UInt,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { actor.yield((.decrement(by: count), nil, file, function, line)) }

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
        let id = UUID()
        log("Waiting", id: id, file: file, function: function, line: line)
        await waiter.send((id, file, function, line))
        do {
            try Task.checkCancellation()
            log("Completed", id: id, file: file, function: function, line: line)
        } catch {
            log("Cancelled", id: id, file: file, function: function, line: line)
            throw error
        }
    }
}

#if canImport(Logging)
import Logging

extension AsyncCountdownEvent {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)",
            "limit": "\(limit)",
            "current_count": "\(currentCount)",
            "initial_count": "\(initialCount)",
        ]
    }
}
#endif
