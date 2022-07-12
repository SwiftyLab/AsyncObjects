import Foundation

public actor AsyncMutex {
    private typealias Continuation = UnsafeContinuation<Void, Error>
    private var continuations: [UUID: Continuation] = [:]
    private var locked: Bool

    private func addContinuation(
        _ continuation: Continuation,
        withKey key: UUID
    ) {
        continuations[key] = continuation
    }

    private func removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
    }

    public init(lockedInitially locked: Bool = true) {
        self.locked = locked
    }

    public func lock() {
        locked = true
    }

    public func release() {
        continuations.forEach { $0.value.resume() }
        continuations = [:]
        locked = false
    }

    public func wait() async {
        guard locked else { return }
        let key = UUID()
        do {
            try await withUnsafeThrowingContinuationCancellationHandler(
                handler: { (continuation: Continuation) in
                    Task { await removeContinuation(withKey: key) }
                },
                { addContinuation($0, withKey: key) }
            )
        } catch {
            debugPrint(
                "Wait on mutex for continuation task with key: \(key)"
                    + " cancelled with error \(error)"
            )
        }
    }

    @discardableResult
    public func wait(
        forNanoseconds duration: UInt64
    ) async -> TaskTimeoutResult {
        guard locked else { return .success }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.wait() }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: duration)
                } catch {}
            }

            for await _ in group.prefix(1) {
                group.cancelAll()
            }
        }
        return locked ? .timedOut : .success
    }
}
