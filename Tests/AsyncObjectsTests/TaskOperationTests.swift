import XCTest
import Dispatch
@testable import AsyncObjects

class TaskOperationTests: XCTestCase {
    #if canImport(Darwin)
    func testTaskOperation() async throws {
        let queue = OperationQueue()
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        XCTAssertTrue(operation.isAsynchronous)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        let time = DispatchTime.now()
        queue.addOperation(operation)
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        await waitForExpectations(timeout: 2)
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        XCTAssertEqual(
            3,
            Int(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / Int(1E9)
        )
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isCancelled)
        switch await operation.result {
        case .success(true): break
        default: XCTFail("Unexpected operation result")
        }
    }

    func testTaskOperationCancellation() async throws {
        let queue = OperationQueue()
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        queue.addOperation(operation)
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        await waitForExpectations(timeout: 2)
        operation.cancel()
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertTrue(operation.isCancelled)
        switch await operation.result {
        case .success(true): XCTFail("Unexpected operation result")
        default: break
        }
    }

    func testThrowingTaskOperation() throws {
        let queue = OperationQueue()
        let operation = TaskOperation {
            try await Self.sleep(seconds: 3)
        }
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        queue.addOperation(operation)
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        waitForExpectations(timeout: 2)
        operation.waitUntilFinished()
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isCancelled)
    }

    func testThrowingTaskOperationCancellation() async throws {
        let queue = OperationQueue()
        let operation = TaskOperation {
            try await Self.sleep(seconds: 3)
        }
        XCTAssertFalse(operation.isExecuting)
        XCTAssertFalse(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
        queue.addOperation(operation)
        expectation(
            for: NSPredicate { _, _ in operation.isExecuting },
            evaluatedWith: nil,
            handler: nil
        )
        await waitForExpectations(timeout: 2)
        operation.cancel()
        await GlobalContinuation<Void, Never>.with { continuation in
            DispatchQueue.global(qos: .default).async {
                operation.waitUntilFinished()
                continuation.resume()
            }
        }
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertTrue(operation.isCancelled)
    }
    #endif

    func testTaskOperationAsyncWait() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        operation.signal()
        await Self.checkExecInterval(
            durationInRange: ...3,
            for: operation.wait
        )
    }

    func testTaskOperationAsyncWaitTimeout() async throws {
        let operation = TaskOperation {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        operation.signal()
        await Self.checkExecInterval(durationInSeconds: 1) {
            await operation.wait(forSeconds: 1)
        }
    }

    func testTaskOperationAsyncWaitWithZeroTimeout() async throws {
        let operation = TaskOperation { /* Do nothing */  }
        operation.signal()
        await Self.checkExecInterval(durationInSeconds: 0) {
            await operation.wait(forNanoseconds: 0)
        }
    }

    func testDeinitWithCancellation() async throws {
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
            XCTAssertNil(operation)
        }
    }

    func testDeinitWithoutCancellation() async throws {
        let operation = TaskOperation { try await Self.sleep(seconds: 1) }
        operation.signal()
        await operation.wait()
        self.addTeardownBlock { [weak operation] in
            XCTAssertNil(operation)
        }
    }

    func createOperationWithChildTasks(
        track: Bool = false
    ) -> TaskOperation<Void> {
        return TaskOperation(trackChildTasks: track) {
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
        await Self.checkExecInterval(durationInSeconds: 0) {
            await operation.wait()
        }
    }

    func testOperationWithTrackingChildTasks() async throws {
        let operation = createOperationWithChildTasks(track: true)
        operation.signal()
        await Self.checkExecInterval(durationInSeconds: 3) {
            await operation.wait()
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
}
