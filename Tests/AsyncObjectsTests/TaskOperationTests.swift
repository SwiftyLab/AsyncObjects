import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
class TaskOperationTests: XCTestCase {

    func testExecution() async throws {
        let operation = TaskOperation {
            (try? await Task.sleep(seconds: 1)) != nil
        }
        XCTAssertTrue(operation.isAsynchronous)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        #if canImport(Darwin)
        let queue = OperationQueue()
        queue.addOperation(operation)
        #else
        operation.start()
        #endif
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await waitUntil(
                    operation,
                    timeout: 3,
                    satisfies: \.isExecuting
                )
            }
            group.addTask {
                await GlobalContinuation<Void, Never>.with { continuation in
                    operation.completionBlock = { continuation.resume() }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isCancelled)
        switch await operation.result {
        case .success(true): break
        default: XCTFail("Unexpected operation result")
        }
    }

    func testThrowingExecution() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 1)
        }
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        #if canImport(Darwin)
        let queue = OperationQueue()
        queue.addOperation(operation)
        #else
        operation.start()
        #endif
        try await waitUntil(operation, timeout: 3, satisfies: \.isExecuting)
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isCancelled)
    }

    func testAsyncWait() async throws {
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        try await operation.wait(forSeconds: 3)
    }

    func testFinisheAsyncdWait() async throws {
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        try await operation.wait(forSeconds: 3)
    }

    func testDeinit() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 1)
        }
        operation.signal()
        try await operation.wait(forSeconds: 5)
        self.addTeardownBlock { [weak operation] in
            operation.assertReleased()
        }
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let operation = TaskOperation {}
                    try await withThrowingTaskGroup(of: Void.self) { g in
                        g.addTask { try await operation.wait(forSeconds: 3) }
                        g.addTask { operation.signal() }
                        try await g.waitForAll()
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

@MainActor
class TaskOperationTimeoutTests: XCTestCase {

    func testWaitTimeout() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 10)
        }
        operation.signal()
        do {
            try await operation.wait(forSeconds: 3)
            XCTFail("Unexpected task progression")
        } catch is DurationTimeoutError {}
    }
}

#if swift(>=5.7)
@MainActor
class TaskOperationClockTimeoutTests: XCTestCase {

    func testWaitTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let operation = TaskOperation {
            try await Task.sleep(until: .now + .seconds(10), clock: clock)
        }
        operation.signal()
        do {
            try await operation.wait(forSeconds: 3, clock: clock)
            XCTFail("Unexpected task progression")
        } catch is TimeoutError<ContinuousClock> {}
    }
}
#endif

@MainActor
class TaskOperationCancellationTests: XCTestCase {

    func testCancellation() async throws {
        let operation = TaskOperation {
            (try? await Task.sleep(seconds: 10)) != nil
        }
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        #if canImport(Darwin)
        let queue = OperationQueue()
        queue.addOperation(operation)
        #else
        operation.start()
        #endif
        try await waitUntil(operation, timeout: 3, satisfies: \.isExecuting)
        operation.cancel()
        try await waitUntil(operation, timeout: 3, satisfies: \.isCancelled)
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        switch await operation.result {
        case .success(true): XCTFail("Unexpected operation result")
        default: break
        }
    }

    func testThrowingCancellation() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 1)
        }
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        #if canImport(Darwin)
        let queue = OperationQueue()
        queue.addOperation(operation)
        #else
        operation.start()
        #endif
        try await waitUntil(operation, timeout: 3, satisfies: \.isExecuting)
        operation.cancel()
        try await waitUntil(operation, timeout: 3, satisfies: \.isCancelled)
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
    }

    func testWaitCancellation() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 1)
        }
        let task = Task.detached {
            try await operation.wait(forSeconds: 3)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testAlreadyCancelledTask() async throws {
        let operation = TaskOperation { try await Task.sleep(seconds: 10) }
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 1)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            try await operation.wait()
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testDeinit() async throws {
        let operation = TaskOperation {
            do {
                try await Task.sleep(seconds: 1)
                XCTFail("Unexpected task progression")
            } catch is CancellationError {}
        }
        operation.signal()
        operation.cancel()
        try await waitUntil(operation, timeout: 3, satisfies: \.isCancelled)
        self.addTeardownBlock { [weak operation] in
            operation.assertReleased()
        }
    }
}

@MainActor
class TaskOperationTaskManagementTests: XCTestCase {

    func testOperationWithoutTrackingChildTasks() async throws {
        let operation = TaskOperation(track: false)
        operation.signal()
        try await operation.wait(forSeconds: 3)
    }

    func testOperationWithTrackingChildTasks() async throws {
        let operation = TaskOperation(track: true)
        operation.signal()
        try await operation.wait(forSeconds: 8)
    }

    func testNotStartedError() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 1)
        }
        let result = await operation.result
        switch result {
        case .failure(let error as EarlyInvokeError):
            XCTAssertFalse(error.localizedDescription.isEmpty)
        default: XCTFail("Unexpected operation result")
        }
    }

    func testNotStartedCancellationError() async throws {
        let operation = TaskOperation {
            try await Task.sleep(seconds: 1)
        }
        operation.cancel()
        let result = await operation.result
        switch result {
        case .failure(let error as CancellationError):
            XCTAssertFalse(error.localizedDescription.isEmpty)
        default: XCTFail("Unexpected operation result")
        }
    }
}

fileprivate extension TaskOperation {

    convenience init(track: Bool) where R == Void {
        self.init(flags: track ? .trackUnstructuredTasks : []) {
            for i in 0..<5 {
                Task {
                    let duration = UInt64(Double(i + 1) * 1E9)
                    try await Task.sleep(nanoseconds: duration)
                }
            }
        }
    }
}
