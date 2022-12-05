import Foundation

#if canImport(Logging)
import Logging

/// A type that emits log messages with specific metadata.
@usableFromInline
protocol Loggable {
    /// Metadata to attach to all log messages for this type.
    var metadata: Logger.Metadata { get }
}

/// An actor type that emits log messages with specific metadata.
@usableFromInline
protocol LoggableActor: Actor {
    /// Metadata to attach to all log messages for this type.
    var metadata: Logger.Metadata { get }
}

@usableFromInline
let logger = Logger(label: "com.SwiftyLab.AsyncObjects")

#if ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_INFO
@usableFromInline
let level: Logger.Level = .info
#elseif ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE
@usableFromInline
let level: Logger.Level = .trace
#elseif ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG
@usableFromInline
let level: Logger.Level = .debug
#else
@usableFromInline
let level: Logger.Level = .info
#endif

extension Loggable {
    /// Log a message attaching the default type specific metadata
    /// and optional identifier.
    ///
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE` is set log level is set to `trace`.
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG` is set log level is set to `debug`.
    /// Otherwise log level is set to `info`.
    ///
    /// - Parameters:
    ///   - message: The message to be logged.
    ///   - id: Optional identifier associated with message.
    ///   - file: The file this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#fileID`).
    ///   - function: The function this log message originates from (there's usually
    ///               no need to pass it explicitly as it defaults to `#function`).
    ///   - line: The line this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#line`).
    @inlinable
    func log(
        _ message: @autoclosure () -> Logger.Message,
        id: UUID? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        var metadata = metadata
        if let id = id { metadata["id"] = "\(id)" }
        logger.log(
            level: level, message(), metadata: metadata,
            file: file, function: function, line: line
        )
    }
}

extension LoggableActor {
    /// Log a message attaching the default type specific metadata
    /// and optional identifier.
    ///
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE` is set log level is set to `trace`.
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG` is set log level is set to `debug`.
    /// Otherwise log level is set to `info`.
    ///
    /// - Parameters:
    ///   - message: The message to be logged.
    ///   - id: Optional identifier associated with message.
    ///   - file: The file this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#fileID`).
    ///   - function: The function this log message originates from (there's usually
    ///               no need to pass it explicitly as it defaults to `#function`).
    ///   - line: The line this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#line`).
    @inlinable
    func log(
        _ message: @autoclosure () -> Logger.Message,
        id: UUID? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        var metadata = metadata
        if let id = id { metadata["id"] = "\(id)" }
        logger.log(
            level: level, message(), metadata: metadata,
            file: file, function: function, line: line
        )
    }
}
#else
/// A type that emits log messages with specific metadata.
@usableFromInline
protocol Loggable {}

/// An actor type that emits log messages with specific metadata.
@usableFromInline
protocol LoggableActor: Actor {}

extension Loggable {
    /// Log a message attaching the default type specific metadata
    /// and optional identifier.
    ///
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE` is set log level is set to `trace`.
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG` is set log level is set to `debug`.
    /// Otherwise log level is set to `info`.
    ///
    /// - Parameters:
    ///   - message: The message to be logged.
    ///   - id: Optional identifier associated with message.
    ///   - file: The file this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#fileID`).
    ///   - function: The function this log message originates from (there's usually
    ///               no need to pass it explicitly as it defaults to `#function`).
    ///   - line: The line this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#line`).
    @inlinable
    func log(
        _ message: @autoclosure () -> String,
        id: UUID? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { /* Do nothing */  }
}

extension LoggableActor {
    /// Log a message attaching the default type specific metadata
    /// and optional identifier.
    ///
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_TRACE` is set log level is set to `trace`.
    /// If `ASYNCOBJECTS_ENABLE_LOGGING_LEVEL_DEBUG` is set log level is set to `debug`.
    /// Otherwise log level is set to `info`.
    ///
    /// - Parameters:
    ///   - message: The message to be logged.
    ///   - id: Optional identifier associated with message.
    ///   - file: The file this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#fileID`).
    ///   - function: The function this log message originates from (there's usually
    ///               no need to pass it explicitly as it defaults to `#function`).
    ///   - line: The line this log message originates from (there's usually
    ///           no need to pass it explicitly as it defaults to `#line`).
    @inlinable
    func log(
        _ message: @autoclosure () -> String,
        id: UUID? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) { /* Do nothing */  }
}
#endif
