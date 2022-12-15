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
/// You increment a semaphore count by calling the ``signal(file:function:line:)`` method
/// and decrement a semaphore count by calling ``wait(file:function:line:)`` method
/// or its timeout variation ``wait(until:tolerance:clock:file:function:line:)``:
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
public actor AsyncSemaphore: AsyncObject, ContinuableCollectionActor,
    LoggableActor
{
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = TrackedContinuation<
        GlobalContinuation<Void, Error>
    >

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
        preinit: @Sendable () -> Void
    ) {
        preinit()
        count -= 1
        log("Adding", id: key, file: file, function: function, line: line)
        guard !continuation.resumed else {
            log(
                "Already resumed, not tracking", id: key,
                file: file, function: function, line: line
            )
            return
        }

        guard count <= 0 else {
            continuation.resume()
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
        incrementCount()
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

    /// Increments semaphore count within limit provided.
    @inlinable
    internal func incrementCount() {
        guard count < limit else { return }
        count += 1
    }

    /// Signals (increments) and releases a semaphore.
    ///
    /// - Parameters:
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func signalSemaphore(file: String, function: String, line: UInt) {
        incrementCount()
        guard !continuations.isEmpty else { return }
        log("Signalling", file: file, function: function, line: line)
        let (key, continuation) = continuations.removeFirst()
        continuation.resume()
        log("Resumed", id: key, file: file, function: function, line: line)
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

    // TODO: Explore alternative cleanup for actor
    // deinit { self.continuations.forEach { $1.cancel() } }

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
        Task {
            await signalSemaphore(file: file, function: function, line: line)
        }
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
        guard count <= 1 else {
            count -= 1
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

extension AsyncSemaphore {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)(\(Unmanaged.passUnretained(self).toOpaque()))",
            "limit": "\(limit)",
            "count": "\(count)",
        ]
    }
}
#endif
