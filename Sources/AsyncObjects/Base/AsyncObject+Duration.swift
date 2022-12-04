public extension AsyncObject {
    /// Waits for the object to green light task execution within the duration.
    ///
    /// Waits asynchronously suspending current  task, instead of blocking any thread.
    /// Depending upon whether wait succeeds or timeout expires result is returned.
    /// `AsyncObject` has to resume the task at a later time depending on its requirement.
    ///
    /// - Parameters:
    ///   - duration: The duration in nano seconds to wait until.
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled or `DurationTimeoutError` if timed out.
    /// - Note: Method might return immediately depending upon the synchronization object requirement.
    @Sendable
    func wait(
        forNanoseconds duration: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        return try await waitForTaskCompletion(
            withTimeoutInNanoseconds: duration,
            file: file, function: function, line: line
        ) { try await self.wait(file: file, function: function, line: line) }
    }
}

/// Waits for multiple objects to green light task execution
/// within provided duration.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns either when all the invocation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - duration: The duration in nano seconds to wait until.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///           or `DurationTimeoutError` if timed out.
@inlinable
@Sendable
public func waitForAll(
    _ objects: [any AsyncObject],
    forNanoseconds duration: UInt64,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForTaskCompletion(withTimeoutInNanoseconds: duration) {
        try await waitForAll(
            objects,
            file: file, function: function, line: line
        )
    }
}

/// Waits for multiple objects to green light task execution
/// within provided duration.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns either when all the invocation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - duration: The duration in nano seconds to wait until.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///            or `DurationTimeoutError` if timed out.
@inlinable
@Sendable
public func waitForAll(
    _ objects: any AsyncObject...,
    forNanoseconds duration: UInt64,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForAll(
        objects, forNanoseconds: duration,
        file: file, function: function, line: line
    )
}

/// Waits for multiple objects to green light task execution
/// by some(provided by count) of them within provided duration.
///
/// Invokes ``AsyncObject/wait(file:function:line:)`` for all objects
/// and returns when some(provided by count) of the invocation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - count: The number of objects to wait for.
///   - duration: The duration in nano seconds to wait until.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///           or `DurationTimeoutError` if timed out.
@inlinable
@Sendable
public func waitForAny(
    _ objects: [any AsyncObject],
    count: Int = 1,
    forNanoseconds duration: UInt64,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForTaskCompletion(withTimeoutInNanoseconds: duration) {
        try await waitForAny(
            objects, count: count,
            file: file, function: function, line: line
        )
    }
}

/// Waits for multiple objects to green light task execution
/// by some(provided by count) of them within provided duration.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns when some(provided by count) of
/// the invocation completes or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - count: The number of objects to wait for.
///   - duration: The duration in nano seconds to wait until.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///           or `DurationTimeoutError` if timed out.
@inlinable
@Sendable
public func waitForAny(
    _ objects: any AsyncObject...,
    count: Int = 1,
    forNanoseconds duration: UInt64,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForAny(
        objects, count: count, forNanoseconds: duration,
        file: file, function: function, line: line
    )
}

/// Waits for the provided task to be completed within the timeout duration.
///
/// Executes the provided tasks and waits until timeout expires.
/// If task doesn't complete within time frame, task is cancelled.
///
/// - Parameters:
///   - timeout: The duration in nano seconds to wait until.
///   - file: The file task passed from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function task passed from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line task passed from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///   - task: The task to execute and wait for completion.
///
/// - Throws: `CancellationError` if cancelled
///           or `DurationTimeoutError` if timed out.
@Sendable
public func waitForTaskCompletion(
    withTimeoutInNanoseconds timeout: UInt64,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    _ task: @escaping @Sendable () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        await GlobalContinuation<Void, Never>.with { continuation in
            group.addTask {
                continuation.resume()
                try await task()
            }
        }
        group.addTask {
            await Task.yield()
            try await Task.sleep(nanoseconds: timeout + 1_000)
            throw DurationTimeoutError(for: timeout, tolerance: 1_000)
        }
        defer { group.cancelAll() }
        try await group.next()
    }
}

/// An error that indicates a task was timed out for provided duration
/// and task specific tolerance.
///
/// This error is also thrown automatically by
/// ``waitForTaskCompletion(withTimeoutInNanoseconds:file:function:line:_:)``,
/// if the task execution exceeds provided time out duration.
///
/// While ``duration`` is user configurable, ``tolerance`` is task specific.
@frozen
public struct DurationTimeoutError: Error, Sendable {
    /// The duration in nano seconds that was provided for timeout operation.
    ///
    /// The total timeout duration takes consideration
    /// of both provided duration and operation specific tolerance:
    ///
    /// total timeout duration = ``duration`` + ``tolerance``
    public let duration: UInt64
    /// The additional tolerance in nano seconds used for timeout operation.
    ///
    /// The total timeout duration takes consideration
    /// of both provided duration and operation specific tolerance:
    ///
    /// total timeout duration = ``duration`` + ``tolerance``
    public let tolerance: UInt64

    /// Creates a new timeout error based on provided duration and task specific tolerance.
    ///
    /// - Parameters:
    ///   - duration: The provided timeout duration in nano seconds.
    ///   - tolerance: The task specific additional margin in nano seconds.
    ///
    /// - Returns: The newly created timeout error.
    public init(for duration: UInt64, tolerance: UInt64 = 0) {
        self.duration = duration
        self.tolerance = tolerance
    }
}
