import Foundation

/// A type representing a unit of work or task that supports cancellation.
///
/// Cancellation should be initiated on invoking ``cancel(file:function:line:)``
/// method. The ``wait(file:function:line:)`` method indicates when task
/// is completed and should support cooperative cancellation.
@rethrows
public protocol Cancellable: Sendable {
    /// Triggers cancellation of work or task.
    ///
    /// The task needs not to be immediately cancelled,
    /// rather the cancellation should be initiated when invoking this method.
    ///
    /// - Parameters:
    ///   - file: The file cancel request originates from.
    ///   - function: The function cancel request originates from.
    ///   - line: The line cancel request originates from.
    ///
    /// - Note: The ``wait(file:function:line:)`` method should handle
    ///         the cancellation cooperatively after this method is invoked.
    @Sendable
    func cancel(file: String, function: String, line: UInt)

    /// Waits asynchronously for the work or task to complete.
    ///
    /// This function returns when task completed successfully
    /// or terminated due to some error.
    ///
    /// - Parameters:
    ///   - file: The file wait request originates from.
    ///   - function: The function wait request originates from.
    ///   - line: The line wait request originates from.
    ///
    /// - Note: This method should handle the cancellation cooperatively after
    ///         ``cancel(file:function:line:)`` method is invoked.
    @Sendable
    func wait(file: String, function: String, line: UInt) async throws
}

extension Task: Cancellable {
    /// Indicates that the task should stop running.
    ///
    /// Task cancellation is cooperative: a task that supports cancellation checks whether
    /// it has been canceled at various points during its work. Calling this method on a task
    /// that doesn’t support cancellation has no effect. Likewise, if the task has already run past
    /// the last point where it would stop early, calling this method has no effect.
    ///
    /// - Parameters:
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @inlinable
    @Sendable
    @_disfavoredOverload
    public func cancel(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.cancel()
    }

    /// Waits asynchronously for the task to complete successfully or cancel with error.
    ///
    /// If the task hasn’t completed, accessing this property waits for it to complete and
    /// its priority increases to that of the current task. Note that this might not be as
    /// effective as creating the task with the correct priority, depending on the executor’s
    /// scheduling details.
    ///
    /// If the task throws an error, this property propagates that error. Tasks that respond
    /// to cancellation by throwing `CancellationError` have that error propagated
    /// here upon cancellation.
    ///
    /// - Parameters:
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: If the task completes with error or cancelled.
    @inlinable
    @Sendable
    public func wait(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        let _ = try await self.value
    }
}

/// Waits asynchronously for the work or task to complete
/// handling cooperative cancellation initiation.
///
/// - Parameters:
///   - work: The work for which completion to wait and handle cooperative cancellation.
///   - id: The identifier associated with work.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: If waiting for the work completes with an error.
@inlinable
func waitHandlingCancelation<C: Cancellable>(
    for work: C,
    associatedId id: UUID,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    try await withTaskCancellationHandler {
        defer {
            log("Finished", id: id, file: file, function: function, line: line)
        }
        try await work.wait(file: file, function: function, line: line)
    } onCancel: {
        work.cancel(file: file, function: function, line: line)
        log(
            "Cancellation initiated", id: id,
            file: file, function: function, line: line
        )
    }
}
