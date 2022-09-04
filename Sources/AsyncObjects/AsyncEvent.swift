#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// An object that controls execution of tasks depending on the signal state.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signalled.
///
/// You can signal event by calling the ``signal()`` method and reset signal by calling ``reset()``.
/// Wait for event signal by calling ``wait()`` method or its timeout variation ``wait(forNanoseconds:)``:
///
/// ```swift
/// // create event with initial state (signalled or not)
/// let event = AsyncEvent(signaledInitially: false)
/// // wait for event to be signalled, fails only if task cancelled
/// try await event.wait()
/// // or wait with some timeout
/// try await event.wait(forNanoseconds: 1_000_000_000)
///
/// // signal event after completing some task
/// event.signal()
/// ```
public actor AsyncEvent: AsyncObject {
    /// The suspended tasks continuation type.
    @usableFromInline
    typealias Continuation = SafeContinuation<GlobalContinuation<Void, Error>>
    /// The platform dependent lock used to synchronize continuations tracking.
    @usableFromInline
    let locker: Locker = .init()
    /// The continuations stored with an associated key for all the suspended task that are waiting for event signal.
    @usableFromInline
    private(set) var continuations: [UUID: Continuation] = [:]
    /// Indicates whether current state of event is signalled.
    @usableFromInline
    var signalled: Bool

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
        guard !continuation.resumed else { return }
        guard !signalled else { continuation.resume(); return }
        continuations[key] = continuation
    }

    /// Remove continuation associated with provided key
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameter key: The key in the map.
    @inlinable
    func _removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
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
        try await Continuation.withCancellation(synchronizedWith: locker) {
            Task { [weak self] in
                await self?._removeContinuation(withKey: key)
            }
        } operation: { continuation in
            Task { [weak self] in
                await self?._addContinuation(continuation, withKey: key)
            }
        }
    }

    /// Resets signal of event.
    @inlinable
    func _reset() {
        signalled = false
    }

    /// Signals the event and resumes all the tasks
    /// suspended and waiting for signal.
    @inlinable
    func _signal() {
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
    public nonisolated func reset() {
        Task { await _reset() }
    }

    /// Signals the event.
    ///
    /// Resumes all the tasks suspended and waiting for signal.
    public nonisolated func signal() {
        Task { await _signal() }
    }

    /// Waits for event signal, or proceeds if already signalled.
    ///
    /// Only waits asynchronously, if event is in non-signaled state,
    /// until event is signalled.
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func wait() async throws {
        guard !signalled else { return }
        try await _withPromisedContinuation()
    }
}
