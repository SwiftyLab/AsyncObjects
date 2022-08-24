/// An object that can be used to track completion of  asynchronous operations and
/// their child tasks.
///
/// Use the `withValue` method on projected value of ``current``
/// to assign a tracker to asynchronous operation. The provided completion executed
/// whenever operation and all the child tasks created by it complete.
///
/// - Important: The provided completion is invoked when object deallocates.
///              Do not keep strong reference of this object, as then object won't
///              deallocate as soon asynchronous operations and their child tasks
///              complete.
final class TaskTracker: Sendable {
    /// The tracker associated with current task.
    ///
    /// Use the `withValue` method to assign a tracker to asynchronous operation.
    /// The provided completion executed whenever operation and all the child tasks
    /// created by it complete.
    ///
    /// - Important: The provided completion is invoked when object deallocates.
    ///              Do not keep strong reference of this object, as then object won't
    ///              deallocate as soon asynchronous operations and their child tasks
    ///              complete.
    @TaskLocal
    static var current: TaskTracker?

    /// The action to complete when task and all its child tasks complete.
    private let fire: @Sendable () -> Void

    /// Creates a new tracker instance that can be used
    /// to track completion of  asynchronous operations
    /// along with their child tasks.
    ///
    /// - Parameter fire: The action to complete when task
    ///                   and all its child tasks complete.
    ///
    /// - Returns: The newly created task tracker.
    ///
    /// - Important: The provided completion is invoked when object deallocates.
    ///              Do not keep strong reference of this object, as then object won't
    ///              deallocate as soon asynchronous operations and their child tasks
    ///              complete.
    init(onComplete fire: @Sendable @escaping () -> Void) {
        self.fire = fire
    }

    deinit { fire() }
}
