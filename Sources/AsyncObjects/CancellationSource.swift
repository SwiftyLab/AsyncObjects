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
public actor CancellationSource: LoggableActor {
    /// All the registered tasks for cooperative cancellation.
    @usableFromInline
    internal private(set) var registeredTasks: [AnyHashable: () -> Void] = [:]
    /// All the linked cancellation sources that cancellation event will be propagated.
    ///
    /// - TODO: Store weak reference for cancellation sources.
    /// ```swift
    /// private var linkedSources: NSHashTable<CancellationSource> = .weakObjects()
    /// ```
    @usableFromInline
    internal private(set) var linkedSources: [CancellationSource] = []

    // MARK: Internal

    /// Add task to registered cooperative cancellation tasks list.
    ///
    /// - Parameters:
    ///   - task: The task to register.
    ///   - file: The file registration request originates from.
    ///   - function: The function registration request originates from.
    ///   - line: The line registration request originates from.
    @inlinable
    internal func add<Success, Failure>(
        task: Task<Success, Failure>,
        file: String, function: String, line: UInt
    ) {
        guard !task.isCancelled else {
            log("Already cancelled", file: file, function: function, line: line)
            return
        }

        registeredTasks[task] = { task.cancel() }
        log("Registered", file: file, function: function, line: line)
    }

    /// Remove task from registered cooperative cancellation tasks list.
    ///
    /// - Parameters:
    ///   - task: The task to remove.
    ///   - file: The file remove request originates from.
    ///   - function: The function remove request originates from.
    ///   - line: The line remove request originates from.
    @inlinable
    internal func remove<Success, Failure>(
        task: Task<Success, Failure>,
        file: String, function: String, line: UInt
    ) {
        registeredTasks.removeValue(forKey: task)
        log("Removed", file: file, function: function, line: line)
    }

    /// Add cancellation source to linked cancellation sources list to propagate cancellation event.
    ///
    /// - Parameters:
    ///   - source: The source to link.
    ///   - file: The file link request originates from.
    ///   - function: The function link request originates from.
    ///   - line: The line link request originates from.
    @inlinable
    internal func addSource(
        _ source: CancellationSource,
        file: String, function: String, line: UInt
    ) {
        linkedSources.append(source)
        log("Added", file: file, function: function, line: line)
    }

    /// Propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - file: The file cancel request originates from.
    ///   - function: The function cancel request originates from.
    ///   - line: The line cancel request originates from.
    @inlinable
    internal func propagateCancellation(
        file: String, function: String, line: UInt
    ) async {
        await withTaskGroup(of: Void.self) { group in
            linkedSources.forEach { s in
                group.addTask {
                    await s.cancelAll(
                        file: file, function: function, line: line
                    )
                }
            }
            await group.waitForAll()
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
        registeredTasks.forEach { $1() }
        registeredTasks = [:]
        await propagateCancellation(file: file, function: function, line: line)
        log("Cancelled", file: file, function: function, line: line)
    }

    // MARK: Public

    /// Creates a new cancellation source object.
    ///
    /// - Returns: The newly created cancellation source.
    public init() {}

    #if swift(>=5.7)
    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    public init(
        linkedWith sources: [CancellationSource],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            await withTaskGroup(of: Void.self) { group in
                sources.forEach { source in
                    group.addTask {
                        await source.addSource(
                            self,
                            file: file, function: function, line: line
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    public init(
        linkedWith sources: CancellationSource...,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(
            linkedWith: sources,
            file: file, function: function, line: line
        )
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
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
    /// - Returns: The newly created cancellation source.
    public init(
        cancelAfterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task { [weak self] in
            try await self?.cancel(
                afterNanoseconds: nanoseconds,
                file: file, function: function, line: line
            )
        }
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object at specified deadline.
    ///
    /// - Parameters:
    ///   - deadline: The instant in the provided clock at which cancellation event triggered.
    ///   - clock: The clock for which cancellation deadline provided.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    @available(swift 5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    public init<C: Clock>(
        at deadline: C.Instant,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task { [weak self] in
            try await self?.cancel(
                at: deadline, clock: clock,
                file: file, function: function, line: line
            )
        }
    }
    #else
    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(
        linkedWith sources: [CancellationSource],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task {
            await withTaskGroup(of: Void.self) { group in
                sources.forEach { source in
                    group.addTask {
                        await source.addSource(
                            self,
                            file: file, function: function, line: line
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameters:
    ///   - sources: The cancellation sources the newly created object will be linked to.
    ///   - file: The file link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function link request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line link request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(
        linkedWith sources: CancellationSource...,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init(
            linkedWith: sources,
            file: file, function: function, line: line
        )
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
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
    /// - Returns: The newly created cancellation source.
    public convenience init(
        cancelAfterNanoseconds nanoseconds: UInt64,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.init()
        Task { [weak self] in
            try await self?.cancel(
                afterNanoseconds: nanoseconds,
                file: file, function: function, line: line
            )
        }
    }
    #endif

    /// Register task for cooperative cancellation when cancellation event received on cancellation source.
    ///
    /// If task completes before cancellation event is triggered, it is automatically unregistered.
    ///
    /// - Parameters:
    ///   - task: The task to register.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    @Sendable
    public nonisolated func register<Success, Failure>(
        task: Task<Success, Failure>,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        Task { [weak self] in
            await self?.add(
                task: task,
                file: file, function: function, line: line
            )

            let _ = await task.result
            await self?.remove(
                task: task,
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

    #if swift(>=5.7)
    /// Trigger cancellation event at provided deadline.
    ///
    /// Initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameters:
    ///   - deadline: The instant in the provided clock at which cancellation event triggered.
    ///   - clock: The clock for which cancellation deadline provided.
    ///   - file: The file cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function cancel request originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line cancel request originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///
    /// - Throws: `CancellationError` if cancelled.
    @available(swift 5.7)
    @available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
    @Sendable
    public func cancel<C: Clock>(
        at deadline: C.Instant,
        clock: C,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        try await Task.sleep(until: deadline, clock: clock)
        await cancelAll(file: file, function: function, line: line)
    }
    #endif
}

public extension Task {
    /// Runs the given non-throwing operation asynchronously as part of a new top-level task on behalf of the current actor,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    init(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async -> Success
    ) where Failure == Never {
        self.init(priority: priority, operation: operation)
        cancellationSource.register(
            task: self,
            file: file,
            function: function,
            line: line
        )
    }

    /// Runs the given throwing operation asynchronously as part of a new top-level task on behalf of the current actor,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    init(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async throws -> Success
    ) where Failure == Error {
        self.init(priority: priority, operation: operation)
        cancellationSource.register(
            task: self,
            file: file,
            function: function,
            line: line
        )
    }

    /// Runs the given non-throwing operation asynchronously as part of a new top-level task,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    static func detached(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async -> Success
    ) -> Self where Failure == Never {
        let task = Task.detached(priority: priority, operation: operation)
        cancellationSource.register(
            task: task,
            file: file,
            function: function,
            line: line
        )
        return task
    }

    /// Runs the given throwing operation asynchronously as part of a new top-level task,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - file: The file task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#fileID`).
    ///   - function: The function task registration originates from (there's usually no need to
    ///               pass it explicitly as it defaults to `#function`).
    ///   - line: The line task registration originates from (there's usually no need to pass it
    ///           explicitly as it defaults to `#line`).
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    static func detached(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        operation: @escaping @Sendable () async throws -> Success
    ) -> Self where Failure == Error {
        let task = Task.detached(priority: priority, operation: operation)
        cancellationSource.register(
            task: task,
            file: file,
            function: function,
            line: line
        )
        return task
    }
}

#if canImport(Logging)
import Logging

extension CancellationSource {
    /// Type specific metadata to attach to all log messages.
    @usableFromInline
    var metadata: Logger.Metadata {
        return [
            "obj": "\(self)(\(Unmanaged.passUnretained(self).toOpaque()))",
            "linked_sources": "\(linkedSources.count)",
            "registered_tasks": "\(registeredTasks.count)",
        ]
    }
}
#endif
