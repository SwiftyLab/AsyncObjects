import Foundation

/// An object that controls execution of tasks depending on the signal state.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signaled.
///
/// You can signal event by calling the ``signal()`` method and reset signal by calling ``reset()``.
/// Wait for event signal by calling ``wait()`` method or its timeout variation ``wait(forNanoseconds:)``.
public actor AsyncEvent: AsyncObject {
    /// The suspended tasks continuation type.
    private typealias Continuation = UnsafeContinuation<Void, Error>
    /// The continuations stored with an associated key for all the suspended task that are waitig for event signal.
    private var continuations: [UUID: Continuation] = [:]
    /// Indicates whether current stateof event is signaled.
    private var signaled: Bool

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
    /// from `continuations` map.
    ///
    /// - Parameter key: The key in the map.
    @inline(__always)
    private func removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
    }

    /// Creates a new event with signal state provided.
    /// By default, event is initially in signaled state.
    ///
    /// - Parameter signaled: The signal state for event.
    /// - Returns: The newly created event.
    public init(signaledInitially signaled: Bool = true) {
        self.signaled = signaled
    }

    deinit { self.continuations.forEach { $0.value.cancel() } }

    /// Resets signal of event.
    ///
    /// After reset, tasks have to wait for event signal to complete.
    @Sendable
    public func reset() {
        signaled = false
    }

    /// Signals the event.
    ///
    /// Resumes all the tasks suspended and waiting for signal.
    @Sendable
    public func signal() {
        continuations.forEach { $0.value.resume() }
        continuations = [:]
        signaled = true
    }

    /// Waits for event signal, or proceeds if already signaled.
    ///
    /// Only waits asynchronously, if event is in non-signaled state,
    /// until event is signaled.
    @Sendable
    public func wait() async {
        guard !signaled else { return }
        let key = UUID()
        try? await withUnsafeThrowingContinuationCancellationHandler(
            handler: { [weak self] (continuation: Continuation) in
                Task { [weak self] in
                    await self?.removeContinuation(withKey: key)
                }
            },
            { [weak self] (continuation: Continuation) in
                Task { [weak self] in
                    await self?.addContinuation(continuation, withKey: key)
                }
            }
        )
    }
}
