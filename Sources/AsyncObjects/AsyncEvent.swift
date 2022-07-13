import Foundation

/// An object that controls execution of tasks depending on the signal state.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signaled.
///
/// You can signal event by calling the ``signal()`` method and reset signal by calling ``reset()``.
/// Wait for event signal by calling ``wait()`` method or its timeout variation ``wait(forNanoseconds:)``.
public actor AsyncEvent {
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

    /// Resets signal of event.
    ///
    /// After reset, tasks have to wait for event signal to complete.
    public func reset() {
        signaled = false
    }

    /// Signals the event.
    ///
    /// Resumes all the tasks suspended and waiting for signal.
    public func signal() {
        continuations.forEach { $0.value.resume() }
        continuations = [:]
        signaled = true
    }

    /// Waits for event signal, or proceeds if already signaled.
    ///
    /// Only waits asynchronously, if event is in non-signaled state,
    /// until event is signaled.
    public func wait() async {
        guard !signaled else { return }
        let key = UUID()
        do {
            try await withUnsafeThrowingContinuationCancellationHandler(
                handler: { (continuation: Continuation) in
                    Task { await removeContinuation(withKey: key) }
                },
                { addContinuation($0, withKey: key) }
            )
        } catch {
            debugPrint(
                "Wait on event for continuation task with key: \(key)"
                + " cancelled with error \(error)"
            )
        }
    }

    /// Waits for event signal within the duration, or proceeds if already signaled.
    ///
    /// Only waits asynchronously, if event is in non-signaled state,
    /// until event is signaled or the provided timeout expires.
    ///
    /// - Parameter duration: The duration in nano seconds to wait until.
    /// - Returns: The result indicating whether wait completed or timed out.
    public func wait(
        forNanoseconds duration: UInt64
    ) async -> TaskTimeoutResult {
        guard !signaled else { return .success }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.wait() }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: duration)
                } catch {}
            }

            for await _ in group.prefix(1) {
                group.cancelAll()
            }
        }
        return signaled ? .success : .timedOut
    }
}
