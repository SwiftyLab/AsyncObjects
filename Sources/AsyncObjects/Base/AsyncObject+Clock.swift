#if swift(>=5.7)
public extension AsyncObject {
    /// Waits for the object to green light task execution within the deadline.
    ///
    /// Waits asynchronously suspending current  task, instead of blocking any thread.
    /// Depending upon whether wait succeeds or timeout expires result is returned.
    /// `AsyncObject` has to resume the task at a later time depending on its requirement.
    ///
    /// - Parameters:
    ///   - deadline: The instant in the provided clock up to which to wait.
    ///   - tolerance: The additional duration in provided clock to wait for timeout.
    ///   - clock: The clock for which timeout deadline provided.
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled or `TimeoutError<C>` if timed out.
    /// - Note: Method might return immediately depending upon the synchronization object requirement.
    @available(swift 5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    @Sendable
    func wait<C: Clock>(
        until deadline: C.Instant,
        tolerance: C.Instant.Duration? = nil,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        return try await waitForTaskCompletion(
            until: deadline, tolerance: tolerance, clock: clock,
            file: file, function: function, line: line
        ) { try await self.wait(file: file, function: function, line: line) }
    }
}

/// Waits for multiple objects to green light task execution
/// within provided deadline.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns either when all the invocation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - deadline: The instant in the provided clock up to which to wait.
///   - tolerance: The additional duration in provided clock to wait for timeout.
///   - clock: The clock for which timeout deadline provided.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///           or `TimeoutError<C>` if timed out.
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@inlinable
@Sendable
public func waitForAll<C: Clock>(
    _ objects: [any AsyncObject],
    until deadline: C.Instant,
    tolerance: C.Instant.Duration? = nil,
    clock: C,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForTaskCompletion(
        until: deadline,
        tolerance: tolerance,
        clock: clock
    ) {
        try await waitForAll(
            objects,
            file: file, function: function, line: line
        )
    }
}

/// Waits for multiple objects to green light task execution
/// within provided deadline.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns either when all the invocation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - deadline: The instant in the provided clock up to which to wait.
///   - tolerance: The additional duration in provided clock to wait for timeout.
///   - clock: The clock for which timeout deadline provided.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///            or `TimeoutError<C>` if timed out.
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@inlinable
@Sendable
public func waitForAll<C: Clock>(
    _ objects: any AsyncObject...,
    until deadline: C.Instant,
    tolerance: C.Instant.Duration? = nil,
    clock: C,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForAll(
        objects,
        until: deadline, tolerance: tolerance, clock: clock,
        file: file, function: function, line: line
    )
}

/// Waits for multiple objects to green light task execution
/// by some(provided by count) of them within provided deadline.
///
/// Invokes ``AsyncObject/wait(file:function:line:)`` for all objects
/// and returns when some(provided by count) of the invocation completes
/// or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - count: The number of objects to wait for.
///   - deadline: The instant in the provided clock up to which to wait.
///   - tolerance: The additional duration in provided clock to wait for timeout.
///   - clock: The clock for which timeout deadline provided.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///           or `TimeoutError<C>` if timed out.
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@inlinable
@Sendable
public func waitForAny<C: Clock>(
    _ objects: [any AsyncObject],
    count: Int = 1,
    until deadline: C.Instant,
    tolerance: C.Instant.Duration? = nil,
    clock: C,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForTaskCompletion(
        until: deadline,
        tolerance: tolerance,
        clock: clock
    ) {
        try await waitForAny(
            objects, count: count,
            file: file, function: function, line: line
        )
    }
}

/// Waits for multiple objects to green light task execution
/// by some(provided by count) of them within provided deadline.
///
/// Invokes ``AsyncObject/wait(file:function:line:)``
/// for all objects and returns when some(provided by count) of
/// the invocation completes or the timeout expires.
///
/// - Parameters:
///   - objects: The objects to wait for.
///   - count: The number of objects to wait for.
///   - deadline: The instant in the provided clock up to which to wait.
///   - tolerance: The additional duration in provided clock to wait for timeout.
///   - clock: The clock for which timeout deadline provided.
///   - file: The file wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function wait request originates from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line wait request originates from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///
/// - Throws: `CancellationError` if cancelled
///           or `TimeoutError<C>` if timed out.
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@inlinable
@Sendable
public func waitForAny<C: Clock>(
    _ objects: any AsyncObject...,
    count: Int = 1,
    until deadline: C.Instant,
    tolerance: C.Instant.Duration? = nil,
    clock: C,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
) async throws {
    return try await waitForAny(
        objects, count: count,
        until: deadline, tolerance: tolerance, clock: clock,
        file: file, function: function, line: line
    )
}

/// Waits for the provided task to be completed within the timeout deadline.
///
/// Executes the provided tasks and waits until timeout deadline.
/// If task doesn't complete within time frame, task is cancelled.
///
/// - Parameters:
///   - deadline: The instant in the provided clock up to which to wait.
///   - tolerance: The additional duration in provided clock to wait for timeout.
///   - clock: The clock for which timeout deadline provided.
///   - file: The file task passed from (there's usually no need to pass it
///           explicitly as it defaults to `#fileID`).
///   - function: The function task passed from (there's usually no need to
///               pass it explicitly as it defaults to `#function`).
///   - line: The line task passed from (there's usually no need to pass it
///           explicitly as it defaults to `#line`).
///   - task: The action to execute and wait for completion result.
///
/// - Returns: The result of the action provided.
/// - Throws: `CancellationError` if cancelled
///           or `TimeoutError<C>` if timed out.
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@Sendable
public func waitForTaskCompletion<C: Clock, T: Sendable>(
    until deadline: C.Instant,
    tolerance: C.Instant.Duration? = nil,
    clock: C,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    _ task: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        await GlobalContinuation<Void, Never>.with { continuation in
            group.addTask {
                continuation.resume()
                return try await task()
            }
        }
        group.addTask {
            await Task.yield()
            try await Task.sleep(
                until: deadline,
                tolerance: tolerance,
                clock: clock
            )
            throw TimeoutError<C>(until: deadline, tolerance: tolerance)
        }
        defer { group.cancelAll() }
        guard
            let result = try await group.next()
        else { throw CancellationError() }
        return result
    }
}

/// An error that indicates a task was timed out for provided deadline
/// and task specific tolerance.
///
/// This error is also thrown automatically by
/// ``waitForTaskCompletion(until:tolerance:clock:file:function:line:_:)``,
/// if the task execution exceeds provided time out deadline.
@available(swift 5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@frozen
public struct TimeoutError<C: Clock>: Error, Sendable {
    /// The deadline as an instant in clock `C` for timeout operation.
    ///
    /// The total timeout deadline takes consideration
    /// of both provided deadline and operation specific tolerance:
    ///
    /// total timeout deadline = ``deadline`` + ``tolerance``
    public let deadline: C.Instant
    /// The additional tolerance as duration for clock `C`
    /// used for timeout operation.
    ///
    /// The total timeout deadline takes consideration
    /// of both provided deadline and operation specific tolerance:
    ///
    /// total timeout deadline = ``deadline`` + ``tolerance``
    public let tolerance: C.Instant.Duration?

    /// Creates a new timeout error based on provided deadline and task specific tolerance.
    ///
    /// - Parameters:
    ///   - deadline: The provided timeout deadline as an instant in clock type `C`.
    ///   - tolerance: The task specific additional margin as a duration for clock type `C` .
    ///
    /// - Returns: The newly created timeout error.
    public init(until deadline: C.Instant, tolerance: C.Instant.Duration? = nil)
    {
        self.deadline = deadline
        self.tolerance = tolerance
    }
}
#endif
