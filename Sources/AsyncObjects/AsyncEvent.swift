import Foundation

/// An object that controls execution of tasks depending on the signal state.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signalled.
///
/// You can signal event by calling the ``signal()`` method and reset signal by calling ``reset()``.
/// Wait for event signal by calling ``wait()`` method or its timeout variation ``wait(forNanoseconds:)``.
public actor AsyncEvent: AsyncObject {
    /// The suspended tasks continuation type.
    private typealias Continuation = GlobalContinuation<Void, Error>
    /// The continuations stored with an associated key for all the suspended task that are waiting for event signal.
    private var continuations: [UUID: Continuation] = [:]
    /// Indicates whether current state of event is signalled.
    private var signalled: Bool

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
    /// from `continuations` map and resumes with `CancellationError`.
    ///
    /// - Parameter key: The key in the map.
    @inline(__always)
    private func removeContinuation(withKey key: UUID) {
        let continuation = continuations.removeValue(forKey: key)
        continuation?.cancel()
    }

    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `removeContinuation`.
    ///
    /// Spins up a new continuation and requests to track it with key by invoking `addContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `removeContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inline(__always)
    private func withPromisedContinuation() async throws {
        let key = UUID()
        try await withTaskCancellationHandler { [weak self] in
            Task { [weak self] in
                await self?.removeContinuation(withKey: key)
            }
        } operation: { () -> Continuation.Success in
            try await Continuation.with { continuation in
                self.addContinuation(continuation, withKey: key)
            }
        }
    }

    /// Creates a new event with signal state provided.
    /// By default, event is initially in signalled state.
    ///
    /// - Parameter signalled: The signal state for event.
    ///
    /// - Returns: The newly created event.
    public init(signaledInitially signalled: Bool = true) {
        self.signalled = signalled
    }

    deinit { self.continuations.forEach { $0.value.cancel() } }

    /// Resets signal of event.
    ///
    /// After reset, tasks have to wait for event signal to complete.
    public func reset() {
        signalled = false
    }

    /// Signals the event.
    ///
    /// Resumes all the tasks suspended and waiting for signal.
    public func signal() {
        continuations.forEach { $0.value.resume() }
        continuations = [:]
        signalled = true
    }

    /// Waits for event signal, or proceeds if already signalled.
    ///
    /// Only waits asynchronously, if event is in non-signaled state,
    /// until event is signalled.
    @Sendable
    public func wait() async {
        guard !signalled else { return }
        try? await withPromisedContinuation()
    }
}
