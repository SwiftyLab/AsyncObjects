#if swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// A type that manages a collection of continuations with an associated key.
///
/// A MUTual EXclusion object is used to synchronize continuations state.
@rethrows
internal protocol ContinuableCollection {
    /// The continuation item type in collection.
    associatedtype Continuation: Continuable
    /// The key type that is associated with each continuation item.
    associatedtype Key: Hashable
    /// The  MUTual EXclusion object type used
    /// to synchronize continuation state.
    associatedtype Lock: Exclusible

    /// The  MUTual EXclusion object used
    /// to synchronize continuation state.
    var locker: Lock { get }
    /// Add continuation with the provided key to collection for tracking.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to add
    ///   - key: The key to associate continuation with.
    func addContinuation(_ continuation: Continuation, withKey key: Key) async
    /// Remove continuation with the associated key from collection out of tracking.
    ///
    /// - Parameter key: The key for continuation to remove.
    func removeContinuation(withKey key: Key) async
    /// Suspends the current task, then calls the given closure with a continuation for the current task.
    ///
    /// - Returns: The value continuation is resumed with.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    func withPromisedContinuation() async rethrows -> Continuation.Success
}

extension ContinuableCollection {
    /// Remove continuation associated with provided key.
    ///
    /// Default implementation that does nothing.
    ///
    /// - Parameter key: The key for continuation to remove.
    func removeContinuation(withKey key: Key) async { /* Do nothing */  }
}

extension ContinuableCollection
where
    Self: AnyObject, Self: Sendable, Continuation: SynchronizedContinuable,
    Continuation: Sendable, Continuation.Value: ThrowingContinuable,
    Continuation.Lock == Lock, Key == UUID
{
    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `removeContinuation`.
    ///
    /// Spins up a new continuation and requests to track it with key by invoking `addContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `removeContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Returns: The value continuation is resumed with.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    func withPromisedContinuation() async rethrows -> Continuation.Success {
        let key = UUID()
        return try await Continuation.withCancellation(
            synchronizedWith: locker
        ) {
            Task { [weak self] in
                await self?.removeContinuation(withKey: key)
            }
        } operation: { continuation in
            Task { [weak self] in
                await self?.addContinuation(continuation, withKey: key)
            }
        }
    }
}
