/// A result value indicating whether a task finished before a specified time.
@frozen
public enum TaskTimeoutResult: Hashable {
    /// Indicates that a task successfully finished
    /// before the specified time elapsed.
    case success
    /// Indicates that a task failed to finish
    /// before the specified time elapsed.
    case timedOut
}

/// An object type that can provide synchonization accross multiple task contexts
///
/// Waiting asynchronously can be done by calling ``wait()`` method,
/// while object decides when to resume task. Similarly, ``signal()`` can be used
/// to indicate resuming of suspended tasks.
public protocol AsyncObject: Sendable {
    /// Signals the object for task synchronization.
    ///
    /// Object might resume suspended tasks
    /// or synchronize tasks differently.
    @Sendable
    func signal() async
    /// Waits for the object to green light task execution.
    ///
    /// Waits asynchronously suspending current  task, instead of blocking any thread.
    /// Async object has to resume the task at a later time depending on its requirement.
    ///
    /// - Note: Method might return immediately depending upon the synchronization object requirement.
    @Sendable
    func wait() async
    /// Waits for the object to green light task execution within the duration.
    ///
    /// Waits asynchronously suspending current  task, instead of blocking any thread within the duration.
    /// Async object has to resume the task at a later time depending on its requirement.
    /// Depending upon whether wait succeeds or timeout expires result is returned.
    ///
    /// - Parameter duration: The duration in nano seconds to wait until.
    /// - Returns: The result indicating whether wait completed or timed out.
    /// - Note: Method might return immediately depending upon the synchronization object requirement.
    @discardableResult
    @Sendable
    func wait(forNanoseconds duration: UInt64) async -> TaskTimeoutResult
}

public extension AsyncObject where Self: AnyObject {
    /// Waits for the object to green light task execution within the duration.
    ///
    /// Waits asynchronously suspending current  task, instead of blocking any thread.
    /// Depending upon whether wait succeeds or timeout expires result is returned.
    /// Async object has to resume the task at a later time depending on its requirement.
    ///
    /// - Parameter duration: The duration in nano seconds to wait until.
    /// - Returns: The result indicating whether wait completed or timed out.
    /// - Note: Method might return immediately depending upon the synchronization object requirement.
    @discardableResult
    @Sendable
    func wait(forNanoseconds duration: UInt64) async -> TaskTimeoutResult {
        return await waitForTaskCompletion(
            withTimeoutInNanoseconds: duration
        ) { [weak self] in
            await self?.wait()
        }
    }
}

/// Waits for multiple objects to green light task execution.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns only when all the invokation completes.
///
/// - Parameter objects: The objects to wait for.
public func waitForAll(_ objects: [any AsyncObject]) async {
    await withTaskGroup(of: Void.self) { group in
        objects.forEach { group.addTask(operation: $0.wait) }
        await group.waitForAll()
    }
}

/// Waits for multiple objects to green light task execution.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns only when all the invokation completes.
///
/// - Parameter objects: The objects to wait for.
public func waitForAll(_ objects: any AsyncObject...) async {
    await waitForAll(objects)
}

/// Waits for multiple objects to green light task execution
/// within provided duration.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns either when all the invokation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - duration: The duration in nano seconds to wait until.
/// - Returns: The result indicating whether wait completed or timed out.
public func waitForAll(
    _ objects: [any AsyncObject],
    forNanoseconds duration: UInt64
) async -> TaskTimeoutResult {
    return await waitForTaskCompletion(withTimeoutInNanoseconds: duration) {
        await waitForAll(objects)
    }
}

/// Waits for multiple objects to green light task execution
/// within provided duration.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns either when all the invokation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - duration: The duration in nano seconds to wait until.
/// - Returns: The result indicating whether wait completed or timed out.
public func waitForAll(
    _ objects: any AsyncObject...,
    forNanoseconds duration: UInt64
) async -> TaskTimeoutResult {
    return await waitForAll(objects, forNanoseconds: duration)
}

/// Waits for multiple objects to green light task execution
/// by either of them.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns when any of the invokation completes.
///
/// - Parameter objects: The objects to wait for.
public func waitForAny(_ objects: [any AsyncObject]) async {
    await withTaskGroup(of: Void.self) { group in
        objects.forEach { group.addTask(operation: $0.wait) }
        for await _ in group.prefix(1) { group.cancelAll() }
    }
}

/// Waits for multiple objects to green light task execution
/// by either of them.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns when any of the invokation completes.
///
/// - Parameter objects: The objects to wait for.
public func waitForAny(_ objects: any AsyncObject...) async {
    await waitForAny(objects)
}

/// Waits for multiple objects to green light task execution
/// by either of them within provided duration.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns when any of the invokation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - duration: The duration in nano seconds to wait until.
/// - Returns: The result indicating whether wait completed or timed out.
public func waitForAny(
    _ objects: [any AsyncObject],
    forNanoseconds duration: UInt64
) async -> TaskTimeoutResult {
    return await waitForTaskCompletion(withTimeoutInNanoseconds: duration) {
        await waitForAny(objects)
    }
}

/// Waits for multiple objects to green light task execution
/// by either of them within provided duration.
///
/// Invokes ``AsyncObject/wait()`` for all objects
/// and returns when any of the invokation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - duration: The duration in nano seconds to wait until.
/// - Returns: The result indicating whether wait completed or timed out.
public func waitForAny(
    _ objects: any AsyncObject...,
    forNanoseconds duration: UInt64
) async -> TaskTimeoutResult {
    return await waitForAny(objects, forNanoseconds: duration)
}

/// Waits for the provided task to be completed within the timeout duration.
///
/// Executes the provided tasks and waits until timeout expires.
/// If task doesn't complete within time frame, task is cancelled.
///
/// - Parameters:
///   - task: The task to execute and wait for completion.
///   - timeout: The duration in nano seconds to wait until.
/// - Returns: The result indicating whether task execution completed
///            or timed out.
@inlinable
public func waitForTaskCompletion(
    withTimeoutInNanoseconds timeout: UInt64,
    _ task: @escaping @Sendable () async -> Void
) async -> TaskTimeoutResult {
    var timedOut = true
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await task()
            return !Task.isCancelled
        }
        group.addTask {
            (try? await Task.sleep(nanoseconds: timeout)) == nil
        }
        for await result in group.prefix(1) {
            timedOut = !result
            group.cancelAll()
        }
    }
    return timedOut ? .timedOut : .success
}
