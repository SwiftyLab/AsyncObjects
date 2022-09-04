import Foundation

/// An object that controls cooperative cancellation of multiple registered tasks and linked object registered tasks.
///
/// An async event suspends tasks if current state is non-signaled and resumes execution when event is signalled.
///
/// You can register tasks for cancellation using the ``register(task:)`` method
/// and link with additional sources by creating object with ``init(linkedWith:)`` method.
/// By calling the ``cancel()`` method all the registered tasks will be cancelled
/// and the cancellation event will be propagated to linked cancellation sources,
/// which in turn cancels their registered tasks and further propagates cancellation.
///
/// - Warning: Cancellation sources propagate cancellation event to other linked cancellation sources.
///            In case of circular dependency between cancellation sources, app will go into infinite recursion.
public actor CancellationSource {
    /// All the registered tasks for cooperative cancellation.
    @usableFromInline
    private(set) var registeredTasks: [AnyHashable: () -> Void] = [:]
    /// All the linked cancellation sources that cancellation event will be propagated.
    ///
    /// - TODO: Store weak reference for cancellation sources.
    /// ```swift
    /// private var linkedSources: NSHashTable<CancellationSource> = .weakObjects()
    /// ```
    @usableFromInline
    private(set) var linkedSources: [CancellationSource] = []

    // MARK: Internal

    /// Add task to registered cooperative cancellation tasks list.
    ///
    /// - Parameter task: The task to register.
    @inlinable
    func _add<Success, Failure>(task: Task<Success, Failure>) {
        guard !task.isCancelled else { return }
        registeredTasks[task] = { task.cancel() }
    }

    /// Remove task from registered cooperative cancellation tasks list.
    ///
    /// - Parameter task: The task to remove.
    @inlinable
    func _remove<Success, Failure>(task: Task<Success, Failure>) {
        registeredTasks.removeValue(forKey: task)
    }

    /// Add cancellation source to linked cancellation sources list to propagate cancellation event.
    ///
    /// - Parameter task: The source to link.
    @inlinable
    func _addSource(_ source: CancellationSource) {
        linkedSources.append(source)
    }

    /// Propagate cancellation to linked cancellation sources.
    @inlinable
    nonisolated func _propagateCancellation() async {
        await withTaskGroup(of: Void.self) { group in
            let linkedSources = await linkedSources
            linkedSources.forEach { group.addTask(operation: $0.cancel) }
            await group.waitForAll()
        }
    }

    /// Trigger cancellation event, initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    @Sendable
    public func _cancel() async {
        registeredTasks.forEach { $1() }
        registeredTasks = [:]
        await _propagateCancellation()
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
    /// - Parameter sources: The cancellation sources the newly created object will be linked to.
    ///
    /// - Returns: The newly created cancellation source.
    public init(linkedWith sources: [CancellationSource]) {
        self.init()
        Task {
            await withTaskGroup(of: Void.self) { group in
                sources.forEach { source in
                    group.addTask { await source._addSource(self) }
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
    /// - Parameter sources: The cancellation sources the newly created object will be linked to.
    ///
    /// - Returns: The newly created cancellation source.
    public init(linkedWith sources: CancellationSource...) {
        self.init(linkedWith: sources)
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
    ///
    /// - Parameter nanoseconds: The delay after which cancellation event triggered.
    ///
    /// - Returns: The newly created cancellation source.
    public init(cancelAfterNanoseconds nanoseconds: UInt64) {
        self.init()
        Task { [weak self] in
            try await self?.cancel(afterNanoseconds: nanoseconds)
        }
    }
    #else
    /// Creates a new cancellation source object linking to all the provided cancellation sources.
    ///
    /// Initiating cancellation in any of the provided cancellation sources
    /// will ensure newly created cancellation source receive cancellation event.
    ///
    /// - Parameter sources: The cancellation sources the newly created object will be linked to.
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(linkedWith sources: [CancellationSource]) {
        self.init()
        Task {
            await withTaskGroup(of: Void.self) { group in
                sources.forEach { source in
                    group.addTask { await source._addSource(self) }
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
    /// - Parameter sources: The cancellation sources the newly created object will be linked to.
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(linkedWith sources: CancellationSource...) {
        self.init(linkedWith: sources)
    }

    /// Creates a new cancellation source object
    /// and triggers cancellation event on this object after specified timeout.
    ///
    /// - Parameter nanoseconds: The delay after which cancellation event triggered.
    ///
    /// - Returns: The newly created cancellation source.
    public convenience init(cancelAfterNanoseconds nanoseconds: UInt64) {
        self.init()
        Task { [weak self] in
            try await self?.cancel(afterNanoseconds: nanoseconds)
        }
    }
    #endif

    /// Register task for cooperative cancellation when cancellation event received on cancellation source.
    ///
    /// If task completes before cancellation event is triggered, it is automatically unregistered.
    ///
    /// - Parameter task: The task to register.
    public nonisolated func register<Success, Failure>(
        task: Task<Success, Failure>
    ) {
        Task { [weak self] in
            await self?._add(task: task)
            let _ = await task.result
            await self?._remove(task: task)
        }
    }

    /// Trigger cancellation event, initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    @Sendable
    public nonisolated func cancel() {
        Task { await _cancel() }
    }

    /// Trigger cancellation event after provided delay,
    /// initiate cooperative cancellation of registered tasks
    /// and propagate cancellation to linked cancellation sources.
    ///
    /// - Parameter nanoseconds: The delay after which cancellation event triggered.
    /// - Throws: `CancellationError` if cancelled.
    @Sendable
    public func cancel(afterNanoseconds nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
        await _cancel()
    }
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
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    init(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        operation: @escaping @Sendable () async -> Success
    ) where Failure == Never {
        self.init(priority: priority, operation: operation)
        cancellationSource.register(task: self)
    }

    /// Runs the given throwing operation asynchronously as part of a new top-level task on behalf of the current actor,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task. Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    init(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        operation: @escaping @Sendable () async throws -> Success
    ) where Failure == Error {
        self.init(priority: priority, operation: operation)
        cancellationSource.register(task: self)
    }

    /// Runs the given non-throwing operation asynchronously as part of a new top-level task,
    /// with the provided cancellation source controlling cooperative cancellation.
    ///
    /// The created task will be cancelled when cancellation event triggered on the provided cancellation source.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - cancellationSource: The cancellation source on which new task will be registered for cancellation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    static func detached(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        operation: @escaping @Sendable () async -> Success
    ) -> Self where Failure == Never {
        let task = Task.detached(priority: priority, operation: operation)
        cancellationSource.register(task: task)
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
    ///   - operation: The operation to perform.
    ///
    /// - Returns: The newly created task.
    @discardableResult
    static func detached(
        priority: TaskPriority? = nil,
        cancellationSource: CancellationSource,
        operation: @escaping @Sendable () async throws -> Success
    ) -> Self where Failure == Error {
        let task = Task.detached(priority: priority, operation: operation)
        cancellationSource.register(task: task)
        return task
    }
}
