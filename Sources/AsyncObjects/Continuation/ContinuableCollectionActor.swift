#if swift(>=5.7)
import Foundation

/// An actor type that manages a collection of continuations with an associated key.
///
/// On `Swift 5.7` and above [actor isolation bug with protocol conformance](https://forums.swift.org/t/actor-isolation-is-broken-by-protocol-conformance/57040)
/// is fixed, and hence original protocol can be used without any issue.
typealias ContinuableCollectionActor = ContinuableCollection
#else
@preconcurrency import Foundation

/// An actor type that manages a collection of continuations with an associated key.
///
/// This is to avoid [actor isolation bug with protocol conformance on older `Swift` versions](https://forums.swift.org/t/actor-isolation-is-broken-by-protocol-conformance/57040).
///
/// While removing continuation, the continuation should be cancelled.
@rethrows
internal protocol ContinuableCollectionActor: Actor {
    /// The continuation item type in collection.
    associatedtype Continuation: Continuable
    /// The key type that is associated with each continuation item.
    associatedtype Key: Hashable

    /// Add continuation with the provided key to collection for tracking.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to add.
    ///   - key: The key to associate continuation with.
    ///   - file: The file add request originates from.
    ///   - function: The function add request originates from.
    ///   - line: The line add request originates from.
    ///   - preinit: The pre-initialization handler to run
    ///              in the beginning of this method.
    ///
    /// - Important: The pre-initialization handler must run
    ///              before any logic in this method.
    func addContinuation(
        _ continuation: Continuation, withKey key: Key,
        file: String, function: String, line: UInt,
        preinit: @Sendable () -> Void
    )
    /// Remove continuation with the associated key from collection out of tracking.
    ///
    /// - Parameters:
    ///   - continuation: The continuation value to remove and cancel.
    ///   - key: The key for continuation to remove.
    ///   - file: The file remove request originates from.
    ///   - function: The function remove request originates from.
    ///   - line: The line remove request originates from.
    func removeContinuation(
        _ continuation: Continuation, withKey key: Key,
        file: String, function: String, line: UInt
    )
    /// Suspends the current task, then calls the given closure with a continuation for the current task.
    ///
    /// - Parameters:
    ///   - key: The key associated to task, that requested suspension.
    ///   - file: The file wait request originates from.
    ///   - function: The function wait request originates from.
    ///   - line: The line wait request originates from.
    ///
    /// - Returns: The value continuation is resumed with.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    func withPromisedContinuation(
        withKey key: Key,
        file: String, function: String, line: UInt
    ) async rethrows -> Continuation.Success
}

extension ContinuableCollectionActor
where
    Continuation: TrackableContinuable,
    Continuation.Value: Sendable & ThrowingContinuable, Key: Sendable,
    Key == Continuation.ID
{
    /// Suspends the current task, then calls the given closure with a throwing continuation for the current task.
    /// Continuation can be cancelled with error if current task is cancelled, by invoking `removeContinuation`.
    ///
    /// Spins up a new continuation and requests to track it with key by invoking `addContinuation`.
    /// This operation cooperatively checks for cancellation and reacting to it by invoking `removeContinuation`.
    /// Continuation can be resumed with error and some cleanup code can be run here.
    ///
    /// - Parameters:
    ///   - key: The key associated to task, that requested suspension.
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The value continuation is resumed with.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    func withPromisedContinuation(
        withKey key: Key,
        file: String, function: String, line: UInt
    ) async rethrows -> Continuation.Success {
        return try await Continuation.withCancellation(id: key) {
            continuation in
            Task { [weak self] in
                await self?.removeContinuation(
                    continuation, withKey: key,
                    file: file, function: function, line: line
                )
            }
        } operation: { continuation, preinit in
            Task { [weak self] in
                await self?.addContinuation(
                    continuation, withKey: key,
                    file: file, function: function, line: line,
                    preinit: preinit
                )
            }
        }
    }
}
#endif
