/// An object that controls cooperative cancellation of multiple registered tasks and linked object registered tasks.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signalled.
///
/// You can register tasks for cancellation using the ``register(task:file:function:line:)`` method
/// and link with additional sources by creating object with ``init(linkedWith:)`` method.
/// By calling the ``cancel(file:function:line:)`` method all the registered tasks will be cancelled
/// and the cancellation event will be propagated to linked cancellation sources,
/// which in turn cancels their registered tasks and further propagates cancellation.
///
/// ```swift
/// // create a root cancellation source
/// let source = CancellationSource()
/// // or a child cancellation source linked with multiple parents
/// let childSource = CancellationSource(linkedWith: source)
///
/// // create task registered with cancellation source
/// let task = Task(cancellationSource: source) {
///   try await Task.sleep(nanoseconds: 1_000_000_000)
/// }
/// // or register already created task with cancellation source
/// source.register(task: task)
///
/// // cancel all registered tasks and tasks registered
/// // in linked cancellation sources
/// source.cancel()
/// // or cancel after some time (fails if calling task cancelled)
/// try await source.cancel(afterNanoseconds: 1_000_000_000)
/// ```
///
/// - Warning: Cancellation sources propagate cancellation event to other linked cancellation sources.
///            In case of circular dependency between cancellation sources, app will go into infinite recursion.
public struct CancellationSource: AsyncObject, Cancellable, Loggable {
    /// The continuation type controlling task group lifetime.
    @usableFromInline
    internal typealias Continuation = GlobalContinuation<Void, Error>
    /// The cancellable work with invocation context.
    @usableFromInline
    internal typealias WorkItem = (
        Cancellable, file: String, function: String, line: UInt
    )

    /// The lifetime task that is cancelled when
    /// `CancellationSource` is cancelled.
    @usableFromInline
    var lifetime: Task<Void, Error>!
    /// The stream continuation used to register work items
    /// for cooperative cancellation.
    @usableFromInline
    var pipe: AsyncStream<WorkItem>.Continuation!

    /// A Boolean value that indicates whether cancellation is already
    /// invoked on the source.
    ///
    /// After the value of this property becomes true, it remains true indefinitely.
    /// There is no way to uncancel on this source. Create a new
    /// `CancellationSource` to manage cancellation of newly spawned
    /// tasks in that case.
    public var isCancelled: Bool { lifetime.isCancelled }

    /// Creates a new cancellation source object.
    ///
    /// - Returns: The newly created cancellation source.
    public init() {
        let stream = AsyncStream<WorkItem> { self.pipe = $0 }
        self.lifetime = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for await (work, file, function, line) in stream {
                    group.addTask {
                        try? await withTaskCancellationHandler {
                            try await work.wait(
                                file: file,
                                function: function,
                                line: line
                            )
                        } onCancel: {
                            work.cancel(
                                file: file,
                                function: function,
                                line: line
                            )
                        }
                    }
                }

                group.cancelAll()
                try await group.waitForAll()
            }
        }
    }

    /// Register cancellable work for cooperative cancellation
    /// when cancellation event received on cancellation source.
    ///
    /// If work completes before cancellation event is triggered, it is automatically unregistered.
    ///
    /// - Parameters:
    ///   - task: The cancellable work to register.
    ///   - file: The file work registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function work registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line work registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    public func register<C: Cancellable>(
        task: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let result = pipe.yield((task, file, function, line))
        switch result {
        case .enqueued:
            log(
                "Registered \(task)",
                file: file, function: function, line: line
            )
        case .dropped, .terminated: fallthrough
        @unknown default:
            task.cancel(file: file, function: function, line: line)
            log(
                "Cancelled \(task) due to result: \(result)",
                file: file, function: function, line: line
            )
        }
    }

    /// Trigger cancellation event, initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    @_implements(AsyncObject,signal(file:function:line:))
    public func cancel(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        guard !lifetime.isCancelled else { return }
        pipe.finish()
        lifetime.cancel()
        log("Cancelled", file: file, function: function, line: line)
    }

    /// Waits until all the registered tasks have been cancelled or completed.
    ///
    /// After ``cancel(file:function:line:)`` is invoked, the cancellation event
    /// is triggered to registered tasks. This function returns, once all the registered tasks
    /// either cooperatively cancelled or completed.
    ///
    /// - Parameters:
    ///   - file: The file wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function wait request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line wait request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    public func wait(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async {
        let _ = await lifetime.result
    }
}

#if canImport(Logging)
import Logging

extension CancellationSource {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)"
        ]
    }
}
#endif
