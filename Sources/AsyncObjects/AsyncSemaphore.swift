import Foundation
import AsyncAlgorithms

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
public final class AsyncSemaphore: AsyncObject, Loggable {
    /// The stream continuation used to send signal event
    /// to resume pending waits.
    let producer: AsyncStream<Void>.Continuation
    /// The channel that controls waiting for signal.
    let consumer: AsyncChannel<Void>

    /// Creates new counting semaphore with an initial value.
    /// By default, initial value is zero.
    ///
    /// Passing zero for the value is useful for when two threads need to reconcile the completion of a particular event.
    /// Passing a value greater than zero is useful for managing a finite pool of resources, where the pool size is equal to the value.
    ///
    /// - Parameter count: The starting value for the semaphore.
    /// - Returns: The newly created semaphore.
    public init(value count: UInt = 0) {
        var continuation: AsyncStream<Void>.Continuation!
        let stream = AsyncStream<Void> { continuation = $0 }
        let channel = AsyncChannel<Void>()
        self.producer = continuation
        self.consumer = channel

        for _ in 0..<count { continuation.yield(()) }
        Task.detached {
            signal: for await _ in stream {
                for await _ in channel {
                    continue signal
                }
            }
        }
    }

    deinit {
        producer.finish()
        consumer.finish()
    }

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
    public func signal(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        log("Signalling", file: file, function: function, line: line)
        producer.yield(())
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
        let id = UUID()
        log("Waiting", id: id, file: file, function: function, line: line)
        await consumer.send(())
        do {
            try Task.checkCancellation()
            log("Resumed", id: id, file: file, function: function, line: line)
        } catch {
            log("Cancelled", id: id, file: file, function: function, line: line)
            throw error
        }
    }
}

#if canImport(Logging)
import Logging

extension AsyncSemaphore {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return ["obj": "\(self)"]
    }
}
#endif
