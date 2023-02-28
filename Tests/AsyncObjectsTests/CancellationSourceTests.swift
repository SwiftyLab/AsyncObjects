import XCTest
@testable import AsyncObjects

@MainActor
class CancellationSourceTests: XCTestCase {

    func testTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        source.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testTaskCancellationWithTimeout() async throws {
        let task = Task { try await Task.sleep(seconds: 10) }
        let source = CancellationSource(cancelAfterNanoseconds: UInt64(1E9))
        source.register(task: task)
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    #if swift(>=5.7)
    func testTaskCancellationWithClockTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let source = CancellationSource(
            at: .now + .seconds(1),
            clock: ContinuousClock.continuous
        )
        let task = Task { try await Task.sleep(seconds: 10, clock: clock) }
        source.register(task: task)
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }
    #endif

    func testTaskCancellationWithLinkedSource() async throws {
        let pSource = CancellationSource()
        let source = CancellationSource(linkedWith: pSource)
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        pSource.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testTaskCancellationWithMultipleLinkedSources() async throws {
        let pSource1 = CancellationSource()
        let pSource2 = CancellationSource()
        let source = CancellationSource(linkedWith: pSource1, pSource2)
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        pSource1.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testDeinit() async throws {
        let source = CancellationSource()
        let task = Task.detached {
            try await Task.sleep(seconds: 10)
            XCTFail("Unexpected task progression")
        }
        source.register(task: task)
        source.cancel()
        try? await task.value
        try await Task.sleep(seconds: 5)
        self.addTeardownBlock { [weak source] in
            source.assertReleased()
        }
    }

    func testAlreadyCancelledTask() async throws {
        let source = CancellationSource()
        let task = Task.detached {
            try await Task.sleep(seconds: 10)
            XCTFail("Unexpected task progression")
        }
        task.cancel()
        source.register(task: task)
        do {
            try await waitUntil(source, timeout: 3) { await $0.isCancelled }
            XCTFail("Unexpected task progression")
        } catch {}
    }

    func testTaskCompletion() async throws {
        let source = CancellationSource()
        let task = Task.detached { try await Task.sleep(seconds: 1) }
        source.register(task: task)
        try await task.value
        source.cancel()
        XCTAssertFalse(task.isCancelled)
    }
}

@MainActor
class CancellationSourceInitializationTests: XCTestCase {

    func testTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task(cancellationSource: source) {
            do {
                try await Task.sleep(seconds: 10)
                XCTFail("Unexpected task progression")
            } catch {}
        }
        source.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testDetachedTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            do {
                try await Task.sleep(seconds: 10)
                XCTFail("Unexpected task progression")
            } catch {}
        }
        source.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testThrowingTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
        }
        source.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testThrowingDetachedTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
        }
        source.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
    }

    func testDeinit() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
            XCTFail("Unexpected task progression")
        }
        source.cancel()
        try await waitUntil(task, timeout: 5) { $0.isCancelled }
        try? await task.value
        try await Task.sleep(seconds: 5)
        self.addTeardownBlock { [weak source] in
            source.assertReleased()
        }
    }
}
