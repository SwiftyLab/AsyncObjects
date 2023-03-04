#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// An object that controls execution of tasks depending on the signal state.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signalled.
///
/// You can signal event by calling the ``signal(file:function:line:)``
/// method and reset signal by calling ``reset(file:function:line:)``.
/// Wait for event signal by calling ``wait(file:function:line:)``
/// method or its timeout variation ``wait(until:tolerance:clock:file:function:line:)``:
///
/// ```swift
/// // create event with initial state (signalled or not)
/// let event = AsyncEvent(signaledInitially: false)
/// // wait for event to be signalled,
/// // fails only if task cancelled
/// try await event.wait()
/// // or wait with some timeout
/// try await event.wait(forNanoseconds: 1_000_000_000)
///
/// // signal event after completing some task
/// event.signal()
/// ```
public actor AsyncEvent: AsyncObject, ContinuableCollectionActor, LoggableActor
{
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = TrackedContinuation<
        GlobalContinuation<Void, Error>
    >

    /// The continuations stored with an associated key for all the suspended task that are waiting for event signal.
    @usableFromInline
    internal private(set) var continuations: [UUID: Continuation] = [:]
    /// Indicates whether current state of event is signalled.
    @usableFromInline
    internal private(set) var signalled: Bool

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
        log("Adding", id: key, file: file, function: function, line: line)
        guard !continuation.resumed else {
            log(
                "Already resumed, not tracking", id: key,
                file: file, function: function, line: line
            )
            return
        }

        guard !signalled else {
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

    /// Resets signal of event.
    ///
    /// - Parameters:
    ///   - file: The file reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function reset originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func resetEvent(file: String, function: String, line: UInt) {
        signalled = false
        log("Reset", file: file, function: function, line: line)
    }

    /// Signals the event and resumes all the tasks
    /// suspended and waiting for signal.
    ///
    /// - Parameters:
    ///   - file: The file signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function signal originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line signal originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    internal func signalEvent(file: String, function: String, line: UInt) {
        log("Signalling", file: file, function: function, line: line)
        continuations.forEach { key, value in
            value.resume()
            log("Resumed", id: key, file: file, function: function, line: line)
        }
        continuations = [:]
        signalled = true
        log("Signalled", file: file, function: function, line: line)
    }

    // MARK: Public

    /// Creates a new event with signal state provided.
    /// By default, event is initially in signalled state.
    ///
    /// - Parameter signalled: The signal state for event.
    /// - Returns: The newly created event.
    public init(signaledInitially signalled: Bool = true) {
        self.signalled = signalled
    }

    // TODO: Explore alternative cleanup for actor
    // deinit { self.continuations.forEach { $1.cancel() } }

    /// Resets signal of event.
    ///
    /// After reset, tasks have to wait for event signal to complete.
    ///
    /// - Parameters:
    ///   - file: The file reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function reset originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line reset originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    public nonisolated func reset(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task { await resetEvent(file: file, function: function, line: line) }
    }

    /// Signals the event.
    ///
    /// Resumes all the tasks suspended and waiting for signal.
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
        Task { await signalEvent(file: file, function: function, line: line) }
    }

    /// Waits for event signal, or proceeds if already signalled.
    ///
    /// Only waits asynchronously, if event is in non-signaled state,
    /// until event is signalled.
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
        guard !signalled else {
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

extension AsyncEvent {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)",
            "signalled": "\(signalled)",
        ]
    }
}
#endif
