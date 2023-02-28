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
public actor CancellationSource: AsyncObject, Cancellable, LoggableActor {
    /// The continuation type controlling task group lifetime.
    @usableFromInline
    internal typealias Continuation = GlobalContinuation<Void, Error>
    /// The function invocation context type for logging.
    @usableFromInline
    internal typealias LogContext = (file: String, function: String, line: UInt)
    /// The cancellable work with invocation context.
    @usableFromInline
    internal typealias WorkItem = (Cancellable, LogContext)

    /// The initialization task that initializes task registration
    /// group and continuation.
    @usableFromInline
    var initializationTask: Task<Void, Never>!
    /// The lifetime task that is cancelled when
    /// `CancellationSource` is cancelled.
    @usableFromInline
    var lifetime: Task<Void, Error>!
    /// The continuation cancelled when `CancellationSource` is cancelled
    /// to trigger cooperative cancellation of registered work items.
    @usableFromInline
    var token: Continuation!
    /// The stream continuation used to register work items
    /// for cooperative cancellation.
    @usableFromInline
    var pipe: AsyncStream<WorkItem>.Continuation!

    /// Whether cancellation is already invoked on the source.
    ///
    /// This property waits until `CancellationSource`
    /// is initialized and returns whther cancellation is invoked.
    public var isCancelled: Bool {
        get async {
            await initializationTask.value
            return lifetime.isCancelled
        }
    }

    // MARK: Internal

    /// Add cancellable work to be registered for cooperative cancellation.
    ///
    /// - Parameters:
    ///   - work: The cancellable work to register.
    ///   - file: The file registration request originates from.
    ///   - function: The function registration request originates from.
    ///   - line: The line registration request originates from.
    @inlinable
    internal func add<C: Cancellable>(
        work: C,
        file: String, function: String, line: UInt
    ) async {
        await initializationTask.value
        let result = pipe.yield((work, (file, function, line)))
        switch result {
        case .enqueued:
            log(
                "Registered \(work)",
                file: file, function: function, line: line
            )
        case .dropped, .terminated: fallthrough
        @unknown default:
            work.cancel(file: file, function: function, line: line)
            log(
                "Cancelled \(work) due to result: \(result)",
                file: file, function: function, line: line
            )
        }
    }

    /// Trigger cancellation event, initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - file: The file cancel request originates from.
    ///   - function: The function cancel request originates from.
    ///   - line: The line cancel request originates from.
    @usableFromInline
    internal func cancelAll(file: String, function: String, line: UInt) async {
        await initializationTask.value
        guard !lifetime.isCancelled else { return }
        pipe.finish()
        token.cancel()
        lifetime.cancel()
        log("Cancelled", file: file, function: function, line: line)
    }

    /// Initialize `token` property to use for cancellation event trigger.
    ///
    /// - Parameter token: The continuation to use
    ///                    to trigger cancellation event.
    @usableFromInline
    func initialize(token: Continuation) {
        self.token = token
    }

    /// Initialize all stored properties required for cacellable work registration
    /// and cancellation event trigger.
    ///
    /// - Parameter initialization: The continuation to resume
    ///                             after initializing all properties.
    @inlinable
    func initialize(resume initialization: Continuation) {
        self.lifetime = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var stream: AsyncStream<WorkItem>!
                try! await Continuation.with { initialization in
                    stream = AsyncStream { continuation in
                        self.pipe = continuation
                        initialization.resume()
                    }
                }
                group.addTask {
                    try await Continuation.with { token in
                        Task {
                            await self.initialize(token: token)
                            initialization.resume()
                        }
                    }
                }

                for await (work, (file, function, line)) in stream {
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
                for try await _ in group {}
            }
        }
    }

    // MARK: Public

    /// Creates a new cancellation source object.
    ///
    /// - Returns: The newly created cancellation source.
    public init() {
        self.initializationTask = Task {
            try! await Continuation.with { initialization in
                Task { await self.initialize(resume: initialization) }
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
    public nonisolated func register<C: Cancellable>(
        task: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task {
            await add(work: task, file: file, function: function, line: line)
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
    public nonisolated func cancel(
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task { await cancelAll(file: file, function: function, line: line) }
    }

    /// Trigger cancellation event after provided delay.
    ///
    /// Initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - nanoseconds: The delay after which cancellation event triggered.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func cancel(
        afterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
        await cancelAll(file: file, function: function, line: line)
    }

    /// Waits until cancellation event triggered.
    ///
    /// After ``cancel(file:function:line:)`` is invoked, the wait completes.
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
        await initializationTask.value
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
