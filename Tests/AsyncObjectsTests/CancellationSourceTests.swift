import XCTest
@testable import AsyncObjects

@MainActor
class CancellationSourceTests: XCTestCase {

    func testTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task { try await Task.sleep(seconds: 3) }
        source.register(task: task)
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithTimeout() async throws {
        let source = CancellationSource(cancelAfterNanoseconds: UInt64(1E9))
        let task = Task { try await Task.sleep(seconds: 3) }
        source.register(task: task)
        try await waitUntil(source, timeout: 5) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
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
        let task = Task { try await Task.sleep(seconds: 3, clock: clock) }
        source.register(task: task)
        try await waitUntil(source, timeout: 5) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }
    #endif

    func testTaskCancellationWithLinkedSource() async throws {
        let parentSource = CancellationSource()
        let source = CancellationSource(linkedWith: parentSource)
        let task = Task { try await Task.sleep(seconds: 3) }
        source.register(task: task)
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        parentSource.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithMultipleLinkedSources() async throws {
        let parentSource1 = CancellationSource()
        let parentSource2 = CancellationSource()
        let source = CancellationSource(
            linkedWith: parentSource1, parentSource2
        )
        let task = Task { try await Task.sleep(seconds: 3) }
        source.register(task: task)
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        parentSource1.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testDeinit() async throws {
        let source = CancellationSource()
        let task = Task.detached {
            try await Task.sleep(seconds: 10)
            XCTFail("Unexpected task progression")
        }
        source.register(task: task)
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        try? await task.value
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
            try await waitUntil(source, timeout: 3) {
                !$0.registeredTasks.isEmpty
            }
            XCTFail("Unexpected task progression")
        } catch {}
    }

    func testTaskCompletion() async throws {
        let source = CancellationSource()
        let task = Task.detached { try await Task.sleep(seconds: 1) }
        source.register(task: task)
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        try await waitUntil(source, timeout: 5) { $0.registeredTasks.isEmpty }
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
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testDetachedTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            do {
                try await Task.sleep(seconds: 10)
                XCTFail("Unexpected task progression")
            } catch {}
        }
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
        }
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingDetachedTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
        }
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        XCTAssertTrue(task.isCancelled)
    }

    func testDeinit() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
            XCTFail("Unexpected task progression")
        }
        try await waitUntil(source, timeout: 3) { !$0.registeredTasks.isEmpty }
        source.cancel()
        try await waitUntil(source, timeout: 3) { $0.registeredTasks.isEmpty }
        try? await task.value
        self.addTeardownBlock { [weak source] in
            source.assertReleased()
        }
    }
}
