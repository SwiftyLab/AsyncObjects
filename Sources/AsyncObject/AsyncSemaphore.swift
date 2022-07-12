import Foundation
import OrderedCollections

actor AsyncSemaphore {
    private typealias Continuation = UnsafeContinuation<Void, Error>
    private var continuations: OrderedDictionary<UUID, Continuation> = [:]
    private var limit: UInt
    private var count: Int

    private func addContinuation(
        _ continuation: Continuation,
        withKey key: UUID
    ) {
        continuations[key] = continuation
    }

    private func removeContinuation(withKey key: UUID) {
        continuations.removeValue(forKey: key)
    }

    public init(value count: UInt = 0) {
        self.limit = count + 1
        self.count = Int(limit)
    }

    public func signal() {
        guard count < limit else { return }
        count += 1
        guard !continuations.isEmpty else { return }
        let (_, continuation) = continuations.removeFirst()
        continuation.resume()
    }

    public func wait() async {
        count -= 1
        if count > 0 { return }
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
                "Wait on semaphore for continuation task with key: \(key)"
                + " cancelled with error \(error)"
            )
        }
    }

    @discardableResult
    public func wait(
        forNanoseconds duration: UInt64
    ) async -> TaskTimeoutResult {
        var timedOut = true
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                [weak self] in await self?.wait()
                return true
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: duration)
                    return false
                } catch {
                    return true
                }
            }

            for await result in group.prefix(1) {
                timedOut = !result
                group.cancelAll()
            }
        }
        return timedOut ? .timedOut : .success
    }
}
