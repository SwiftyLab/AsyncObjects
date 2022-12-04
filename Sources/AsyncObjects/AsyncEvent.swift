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
public actor AsyncEvent: AsyncObject, ContinuableCollection {
    /// The suspended tasks continuation type.
    @usableFromInline
    internal typealias Continuation = SafeContinuation<
        GlobalContinuation<Void, Error>
    >
    /// The platform dependent lock used to synchronize continuations tracking.
    @usableFromInline
    internal let locker: Locker = .init()
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
    @inlinable
    internal func addContinuation(
        _ continuation: Continuation,
        withKey key: UUID
    ) {
        guard !continuation.resumed else { return }
        guard !signalled else { continuation.resume(); return }
        continuations[key] = continuation
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    internal func removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
    }

    /// Resets signal of event.
    @inlinable
    internal func resetEvent() {
        signalled = false
    }

    /// Signals the event and resumes all the tasks
    /// suspended and waiting for signal.
    @inlinable
    internal func signalEvent() {
        continuations.forEach { $0.value.resume() }
        continuations = [:]
        signalled = true
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

    deinit { self.continuations.forEach { $0.value.cancel() } }

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
        Task { await resetEvent() }
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
        Task { await signalEvent() }
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
        guard !signalled else { return }
        try await withPromisedContinuation()
    }
}
