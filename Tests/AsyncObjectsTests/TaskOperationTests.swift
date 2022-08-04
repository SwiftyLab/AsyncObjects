import XCTest
import Dispatch
@testable import AsyncObjects

#if canImport(Darwin)
class TaskOperationTests: XCTestCase {

    func testTaskOperation() async throws {
        let queue = OperationQueue()
        let operation = TaskOperation(queue: .global(qos: .background)) {
            (try? await Task.sleep(nanoseconds: UInt64(3E9))) != nil
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
        operation.waitUntilFinished()
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
        default: XCTFail()
        }
    }

    func testTaskOperationCancellation() async throws {
        let queue = OperationQueue()
        let operation = TaskOperation(queue: .global(qos: .background)) {
            (try? await Task.sleep(nanoseconds: UInt64(3E9))) != nil
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
        operation.waitUntilFinished()
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertTrue(operation.isCancelled)
        switch await operation.result {
        case .success(true): XCTFail()
        default: break
        }
    }

    func testThrowingTaskOperation() throws {
        let queue = OperationQueue()
        let operation = TaskOperation(queue: .global(qos: .background)) {
            try await Task.sleep(nanoseconds: UInt64(3E9))
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
            try await Task.sleep(nanoseconds: UInt64(3E9))
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
        operation.waitUntilFinished()
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        XCTAssertTrue(operation.isCancelled)
    }

    func testTaskOperationAsyncWait() async throws {
        let operation = TaskOperation(queue: .global(qos: .background)) {
            (try? await Task.sleep(nanoseconds: UInt64(3E9))) != nil
        }
        operation.signal()
        await checkExecInterval(durationInRange: ...3, for: operation.wait)
    }

    func testTaskOperationAsyncWaitTimeout() async throws {
        let operation = TaskOperation(queue: .global(qos: .background)) {
            (try? await Task.sleep(nanoseconds: UInt64(10E9))) != nil
        }
        operation.signal()
        await checkExecInterval(durationInSeconds: 3) {
            await operation.wait(forNanoseconds: UInt64(3E9))
        }
    }

    func testTaskOperationAsyncWaitWithZeroTimeout() async throws {
        let operation = TaskOperation(queue: .global(qos: .background)) {
            // Do nothing
        }
        operation.signal()
        await checkExecInterval(durationInSeconds: 0) {
            await operation.wait(forNanoseconds: 0)
        }
    }
}
#endif
