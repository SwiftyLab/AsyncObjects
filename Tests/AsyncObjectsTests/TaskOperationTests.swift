import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
class TaskOperationTests: XCTestCase {

    func testTaskOperation() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
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
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isCancelled)
        switch await operation.result {
        case .success(true): break
        default: XCTFail("Unexpected operation result")
        }
    }

    func testThrowingTaskOperation() async throws {
        let operation = TaskOperation {
            try await Self.sleep(seconds: 3)
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
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
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

    func testTaskOperationAsyncWait() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        operation.signal()
        try await Self.checkExecInterval(
            durationInRange: ...3
        ) { try await operation.wait() }
    }

    func testDeinit() async throws {
        let operation = TaskOperation { try await Self.sleep(seconds: 1) }
        operation.signal()
        try await operation.wait()
        self.addTeardownBlock { [weak operation] in
            try await Self.sleep(seconds: 1)
            XCTAssertNil(operation)
        }
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let operation = TaskOperation {}
                    try await Self.checkExecInterval(durationInSeconds: 0) {
                        try await withThrowingTaskGroup(of: Void.self) { g in
                            g.addTask { try await operation.wait() }
                            g.addTask { operation.signal() }
                            try await g.waitForAll()
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

@MainActor
class TaskOperationTimeoutTests: XCTestCase {

    func testWait() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 1)) != nil
        }
        operation.signal()
        try await Self.checkExecInterval(durationInSeconds: 1) {
            try await operation.wait(forSeconds: 2)
        }
    }

    func testFinishedWait() async throws {
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await operation.wait(forNanoseconds: 2)
        }
    }

    func testWaitTimeout() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        operation.signal()
        await Self.checkExecInterval(durationInSeconds: 1) {
            do {
                try await operation.wait(forSeconds: 1)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == DurationTimeoutError.self)
            }
        }
    }

    func testWaitZeroTimeout() async throws {
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await operation.wait(forNanoseconds: 0)
        }
    }
}

#if swift(>=5.7)
@MainActor
class TaskOperationClockTimeoutTests: XCTestCase {

    func testWait() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 1, clock: clock)) != nil
        }
        operation.signal()
        try await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            try await operation.wait(forSeconds: 2, clock: clock)
        }
    }

    func testFinishedWait() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        try await Self.checkExecInterval(duration: .seconds(0), clock: clock) {
            try await operation.wait(forSeconds: 2, clock: clock)
        }
    }

    func testWaitTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3, clock: clock)) != nil
        }
        operation.signal()
        await Self.checkExecInterval(duration: .seconds(1), clock: clock) {
            do {
                try await operation.wait(forSeconds: 1, clock: clock)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(
                    type(of: error) == TimeoutError<ContinuousClock>.self
                )
            }
        }
    }

    func testWaitZeroTimeout() async throws {
        guard
            #available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
        else {
            throw XCTSkip("Clock API not available")
        }
        let clock: ContinuousClock = .continuous
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        try await Self.checkExecInterval(duration: .seconds(0), clock: clock) {
            try await operation.wait(forSeconds: 0, clock: clock)
        }
    }
}
#endif

@MainActor
class TaskOperationCancellationTests: XCTestCase {

    func testCancellation() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
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
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
        operation.cancel()
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        expectation(
            for: NSPredicate { _, _ in operation.isCancelled },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        switch await operation.result {
        case .success(true): XCTFail("Unexpected operation result")
        default: break
        }
    }

    func testThrowingCancellation() async throws {
        let operation = TaskOperation {
            try await Self.sleep(seconds: 3)
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
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
        operation.cancel()
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        expectation(
            for: NSPredicate { _, _ in operation.isCancelled },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
    }

    func testWaitCancellation() async throws {
        let operation = TaskOperation { try await Self.sleep(seconds: 10) }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                try await operation.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testAlreadyCancelledTask() async throws {
        let operation = TaskOperation { try await Self.sleep(seconds: 10) }
        let task = Task.detached {
            try await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                try await operation.wait()
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Unexpected task progression")
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testDeinit() async throws {
        let operation = TaskOperation {
            do {
                try await Self.sleep(seconds: 2)
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == CancellationError.self)
            }
        }
        operation.signal()
        self.addTeardownBlock { [weak operation] in
            try await Self.sleep(seconds: 1)
            XCTAssertNil(operation)
        }
    }
}

@MainActor
class TaskOperationTaskManagementTests: XCTestCase {

    func createOperationWithChildTasks(
        track: Bool = false
    ) -> TaskOperation<Void> {
        return TaskOperation(flags: track ? .trackUnstructuredTasks : []) {
            Task {
                try await Self.sleep(seconds: 1)
            }
            Task {
                try await Self.sleep(seconds: 2)
            }
            Task {
                try await Self.sleep(seconds: 3)
            }
            Task.detached {
                try await Self.sleep(seconds: 5)
            }
        }
    }

    func testOperationWithoutTrackingChildTasks() async throws {
        let operation = createOperationWithChildTasks(track: false)
        operation.signal()
        try await Self.checkExecInterval(durationInSeconds: 0) {
            try await operation.wait()
        }
    }

    func testOperationWithTrackingChildTasks() async throws {
        let operation = createOperationWithChildTasks(track: true)
        operation.signal()
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await operation.wait()
        }
    }

    func testNotStartedError() async throws {
        let operation = TaskOperation { try await Self.sleep(seconds: 1) }
        let result = await operation.result
        switch result {
        case .success: XCTFail("Unexpected operation result")
        case .failure(let error):
            XCTAssertTrue(type(of: error) == EarlyInvokeError.self)
            print(
                "[\(#function)] [\(type(of: error))] \(error.localizedDescription)"
            )
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testNotStartedCancellationError() async throws {
        let operation = TaskOperation { try await Self.sleep(seconds: 1) }
        operation.cancel()
        let result = await operation.result
        switch result {
        case .success: XCTFail("Unexpected operation result")
        case .failure(let error):
            XCTAssertTrue(type(of: error) == CancellationError.self)
            print(
                "[\(#function)] [\(type(of: error))] \(error.localizedDescription)"
            )
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
