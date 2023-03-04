import XCTest
@testable import AsyncObjects

@MainActor
class CancellationSourceTests: XCTestCase {

    func testTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        source.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithTimeout() async throws {
        let task = Task { try await Task.sleep(seconds: 10) }
        let source = CancellationSource(cancelAfterNanoseconds: UInt64(1E9))
        source.register(task: task)
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
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
        let task = Task { try await Task.sleep(seconds: 10, clock: clock) }
        source.register(task: task)
        try await source.wait(forSeconds: 5, clock: clock)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }
    #endif

    func testTaskCancellationWithLinkedSource() async throws {
        let pSource = CancellationSource()
        let source = CancellationSource(linkedWith: pSource)
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        pSource.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithMultipleLinkedSources() async throws {
        let pSource1 = CancellationSource()
        let pSource2 = CancellationSource()
        let source = CancellationSource(linkedWith: pSource1, pSource2)
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        pSource1.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
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
            try await waitUntil(source, timeout: 3) { $0.isCancelled }
            XCTFail("Unexpected task progression")
        } catch {}
    }

    func testTaskCompletion() async throws {
        let source = CancellationSource()
        let task = Task.detached { try await Task.sleep(seconds: 1) }
        source.register(task: task)
        try await task.value
        source.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        try await task.value
    }

    func testConcurrentCancellation() async throws {
        let source = CancellationSource()
        let task = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { source.cancel() } }
            await group.waitForAll()
        }
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }

    func testRegistrationAfterCancellation() async throws {
        let source = CancellationSource()
        let task = Task { try await Task.sleep(seconds: 10) }
        source.cancel()
        source.register(task: task)
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }

    func testMultipleTaskCancellation() async throws {
        let source = CancellationSource()
        let task1 = Task { try await Task.sleep(seconds: 10) }
        let task2 = Task { try await Task.sleep(seconds: 10) }
        let task3 = Task { try await Task.sleep(seconds: 10) }
        source.register(task: task1)
        source.register(task: task2)
        source.register(task: task3)
        source.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task1.isCancelled)
        XCTAssertTrue(task2.isCancelled)
        XCTAssertTrue(task3.isCancelled)
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
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
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
        source.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
        }
        source.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingDetachedTaskCancellation() async throws {
        let source = CancellationSource()
        let task = Task.detached(cancellationSource: source) {
            try await Task.sleep(seconds: 10)
        }
        source.cancel()
        try await source.wait(forSeconds: 5)
        XCTAssertTrue(source.isCancelled)
        XCTAssertTrue(task.isCancelled)
    }
}
