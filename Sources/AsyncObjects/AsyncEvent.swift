import Foundation
import AsyncAlgorithms

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
public final class AsyncEvent: AsyncObject, Loggable {
    /// The stream continuation that updates state change
    /// info for `AsyncEvent`.
    @usableFromInline
    let transmitter: AsyncStream<Bool>.Continuation
    /// The channel that controls waiting on the `AsyncEvent`.
    /// The waiting completes when `AsyncEvent` is signalled.
    let waiter: AsyncChannel<Void>

    /// Creates a new event with signal state provided.
    /// By default, event is initially in signalled state.
    ///
    /// - Parameter signalled: The signal state for event.
    /// - Returns: The newly created event.
    public init(signaledInitially signalled: Bool = true) {
        var continuation: AsyncStream<Bool>.Continuation!
        let stream = AsyncStream<Bool> { continuation = $0 }
        let channel = AsyncChannel<Void>()
        self.transmitter = continuation
        self.waiter = channel

        Task.detached {
            var state = signalled
            var wt = state ? Task { for await _ in channel { continue } } : nil
            for await signal in stream {
                guard state != signal else { continue }
                state = signal
                guard state else { wt?.cancel(); continue }
                wt = Task { for await _ in channel { continue } }
            }
            wt?.cancel()
        }
    }

    deinit { self.transmitter.finish() }

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
    @inlinable
    public nonisolated func reset(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { transmitter.yield(false) }

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
    @inlinable
    public nonisolated func signal(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { transmitter.yield(true) }

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
        let id = UUID()
        log("Waiting", id: id, file: file, function: function, line: line)
        await waiter.send(())
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
