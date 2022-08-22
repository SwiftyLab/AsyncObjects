import XCTest
import Dispatch
@testable import AsyncObjects

#if canImport(Darwin)
class TaskOperationTests: XCTestCase {

    func testTaskOperation() async throws {
        let queue = OperationQueue()
        let operation = TaskOperation(queue: .global(qos: .background)) {
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
        let operation = TaskOperation(queue: .global(qos: .background)) {
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
        let operation = TaskOperation(queue: .global(qos: .background)) {
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
        let operation = TaskOperation(queue: .global(qos: .background)) {
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

    func testTaskOperationAsyncWait() async throws {
        let operation = TaskOperation(queue: .global(qos: .background)) {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        operation.signal()
        await checkExecInterval(durationInRange: ...3, for: operation.wait)
    }

    func testTaskOperationAsyncWaitTimeout() async throws {
        let operation = TaskOperation(queue: .global(qos: .background)) {
            (try? await Self.sleep(seconds: 3)) != nil
        }
        operation.signal()
        await Self.checkExecInterval(durationInSeconds: 1) {
            await operation.wait(forSeconds: 1)
        }
    }

    func testTaskOperationAsyncWaitWithZeroTimeout() async throws {
        let operation = TaskOperation(queue: .global(qos: .background)) {
            // Do nothing
        }
        operation.signal()
        await Self.checkExecInterval(durationInSeconds: 0) {
            await operation.wait(forNanoseconds: 0)
        }
    }
}
#endif
