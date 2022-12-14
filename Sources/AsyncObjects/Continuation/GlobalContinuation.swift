#if swift(>=5.7)
#if DEBUG || ASYNCOBJECTS_USE_CHECKEDCONTINUATION
/// The continuation type used in ``AsyncObjects`` package.
///
/// In `DEBUG` mode or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on
/// `CheckedContinuation` is used.
///
/// In `RELEASE` mode and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION`
/// flag `UnsafeContinuation` is used.
public typealias GlobalContinuation<T, E: Error> = CheckedContinuation<T, E>

extension CheckedContinuation: Continuable {}

extension CheckedContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with a checked throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `CheckedContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    @_unsafeInheritExecutor
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async throws -> T {
        return try await withCheckedThrowingContinuation(
            function: function,
            body
        )
    }
}

extension CheckedContinuation: NonThrowingContinuable where E == Never {
    /// Suspends the current task, then calls the given closure
    /// with a checked non-throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `CheckedContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    @_unsafeInheritExecutor
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async -> T {
        return await withCheckedContinuation(function: function, body)
    }
}
#else
/// The continuation type used in ``AsyncObjects`` package.
///
/// In `DEBUG` mode or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on
/// `CheckedContinuation` is used.
///
/// In `RELEASE` mode and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION`
/// flag `UnsafeContinuation` is used.
public typealias GlobalContinuation<T, E: Error> = UnsafeContinuation<T, E>

extension UnsafeContinuation: Continuable {}

extension UnsafeContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes an `UnsafeContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    @_unsafeInheritExecutor
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async throws -> T {
        return try await withUnsafeThrowingContinuation(body)
    }
}

extension UnsafeContinuation: NonThrowingContinuable where E == Never {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe non-throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes an `UnsafeContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    @_unsafeInheritExecutor
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async -> T {
        return await withUnsafeContinuation(body)
    }
}
#endif
#else
#if DEBUG || ASYNCOBJECTS_USE_CHECKEDCONTINUATION
/// The continuation type used in ``AsyncObjects`` package.
///
/// In `DEBUG` mode or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on
/// `CheckedContinuation` is used.
///
/// In `RELEASE` mode and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION`
/// flag `UnsafeContinuation` is used.
public typealias GlobalContinuation<T, E: Error> = CheckedContinuation<T, E>

extension CheckedContinuation: Continuable {}

extension CheckedContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with a checked throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `CheckedContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async throws -> T {
        return try await withCheckedThrowingContinuation(
            function: function,
            body
        )
    }
}

extension CheckedContinuation: NonThrowingContinuable where E == Never {
    /// Suspends the current task, then calls the given closure
    /// with a checked non-throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// `CheckedContinuation` logs messages proving additional info on these errors.
    /// Once all errors resolved, use `UnsafeContinuation` in release mode to benefit improved performance
    /// at the loss of additional runtime checks.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes a `CheckedContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async -> T {
        return await withCheckedContinuation(function: function, body)
    }
}
#else
/// The continuation type used in ``AsyncObjects`` package.
///
/// In `DEBUG` mode or if `ASYNCOBJECTS_USE_CHECKEDCONTINUATION` flag turned on
/// `CheckedContinuation` is used.
///
/// In `RELEASE` mode and in absence of `ASYNCOBJECTS_USE_CHECKEDCONTINUATION`
/// flag `UnsafeContinuation` is used.
public typealias GlobalContinuation<T, E: Error> = UnsafeContinuation<T, E>

extension UnsafeContinuation: Continuable {}

extension UnsafeContinuation: ThrowingContinuable where E == Error {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes an `UnsafeContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    /// - Throws: If `resume(throwing:)` is called on the continuation, this function throws that error.
    @inlinable
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async throws -> T {
        return try await withUnsafeThrowingContinuation(body)
    }
}

extension UnsafeContinuation: NonThrowingContinuable where E == Never {
    /// Suspends the current task, then calls the given closure
    /// with an unsafe non-throwing continuation for the current task.
    ///
    /// The continuation must be resumed exactly once, subsequent resumes will cause runtime error.
    /// Use `CheckedContinuation` to capture relevant data in case of runtime errors.
    ///
    /// - Parameters:
    ///   - file: The file from which suspension requested.
    ///   - function: A string identifying the declaration
    ///               that is the notional source for the continuation,
    ///               used to identify the continuation in runtime diagnostics
    ///               related to misuse of this continuation.
    ///   - line: The line from which suspension requested.
    ///   - body: A closure that takes an `UnsafeContinuation` parameter.
    ///           You must resume the continuation exactly once.
    ///
    /// - Returns: The value passed to the continuation by the closure.
    @inlinable
    public static func with(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        _ body: (Self) -> Void
    ) async -> T {
        return await withUnsafeContinuation(body)
    }
}
#endif
#endif
