/// An object type that can provide synchronization across multiple task contexts
///
/// Waiting asynchronously can be done by calling ``wait(file:function:line:)`` method,
/// while object decides when to resume task. Similarly, ``signal(file:function:line:)``
/// can be used to indicate resuming suspended tasks.
@rethrows
public protocol AsyncObject: Sendable {
    /// Signals the object for task synchronization.
    ///
    /// Object might resume suspended tasks
    /// or synchronize tasks differently.
    ///
    /// - Parameters:
    ///   - file: The file signal originates from.
    ///   - function: The function signal originates from.
    ///   - line: The line signal originates from.
    @Sendable
    func signal(file: String, function: String, line: UInt)
    /// Waits for the object to green light task execution.
    ///
    /// Waits asynchronously suspending current  task, instead of blocking any thread.
    /// `AsyncObject` has to resume the task at a later time depending on its requirement.
    ///
    /// Might throw some error or never throws depending on implementation.
    ///
    /// - Parameters:
    ///   - file: The file wait request originates from.
    ///   - function: The function wait request originates from.
    ///   - line: The line signal wait request originates from.
    ///
    /// - Note: Method might return immediately depending upon the synchronization object requirement.
    @Sendable
    func wait(file: String, function: String, line: UInt) async throws
}

/// Waits for multiple objects to green light task execution.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns only when all the invocation completes.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled.
@inlinable
@Sendable
public func waitForAll(
    _ objects: [any AsyncObject],
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        objects.forEach { obj in
            group.addTask {
                try await obj.wait(file: file, function: function, line: line)
            }
        }
        try await group.waitForAll()
    }
}

/// Waits for multiple objects to green light task execution.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns only when all the invocation completes.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled.
@inlinable
@Sendable
public func waitForAll(
    _ objects: any AsyncObject...,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    try await waitForAll(objects, file: file, function: function, line: line)
}

/// Waits for multiple objects to green light task execution
/// by some(provided by count) of them.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns when some(provided by count)
/// of the invocation completes.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - count: The number of objects to wait for.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled.
@inlinable
@Sendable
public func waitForAny(
    _ objects: [any AsyncObject],
    count: Int = 1,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        objects.forEach { obj in
            group.addTask {
                try await obj.wait(file: file, function: function, line: line)
            }
        }
        for _ in 0..<count { try await group.next() }
        group.cancelAll()
    }
}

/// Waits for multiple objects to green light task execution
/// by some(provided by count) of them.
///
/// Invokes ``AsyncObject/wait(file:function:line:)`` for all objects
/// and returns when some(provided by count) of the invocation completes.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - count: The number of objects to wait for.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled.
@inlinable
@Sendable
public func waitForAny(
    _ objects: any AsyncObject...,
    count: Int = 1,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    try await waitForAny(
        objects, count: count,
        file: file, function: function, line: line
    )
}
