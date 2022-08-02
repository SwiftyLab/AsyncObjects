import XCTest
@testable import AsyncObjects

class TaskQueueTests: XCTestCase {

    func testSignalingQueueDoesNothing() async {
        let queue = TaskQueue()
        await queue.signal()
        let barriered = await queue.barriered
        XCTAssertFalse(barriered)
    }

    func testSignalingLockedQueueDoesNothing() async throws {
        let queue = TaskQueue()
        Task.detached {
            try await queue.exec(barrier: true) {
                try await Task.sleep(nanoseconds: UInt64(5E9))
            }
        }
        try await Task.sleep(nanoseconds: UInt64(1E9))
        await queue.signal()
        let barriered = await queue.barriered
        XCTAssertTrue(barriered)
    }

    func testWaitOnQueue() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task started before wait
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask { await queue.wait() }
                try await group.waitForAll()
            }
        }
    }

    func testWaitTimeoutOnQueue() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task started before wait
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask { await queue.wait(forNanoseconds: UInt64(3E9)) }
                for try await _ in group.prefix(1) {
                    group.cancelAll()
                }
            }
        }
    }

    func testExecutionOfTwoBarriers() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 10) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskBeforeBarrier() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 5) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task added after concurrent task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testExecutionOfTaskAfterBarrier() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 10) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                // To make sure barrier task started before adding new task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    func testCancellationOfBarrierTaskWithoutBlockingQueue() async throws {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 7) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // To make sure cancellation task started before adding barrier task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels barrier task
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Task.sleep(nanoseconds: UInt64(5E9))
                }
            }
        }
    }

    func testCancellationOfMultipleBarrierTasksWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 8) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // To make sure cancellation task started before adding barrier task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels barrier tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Task.sleep(nanoseconds: UInt64(5E9))
                }
            }
        }
    }

    func
        testCancellationOfMultipleBarrierTasksAndOneConcurrentTaskWithoutBlockingQueue()
        async throws
    {
        let queue = TaskQueue()
        try await checkExecInterval(durationInSeconds: 8) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    // Throws error for waiting method
                    throw CancellationError()
                }
                // To make sure cancellation task started before adding barrier task
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec(barrier: true) {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                group.addTask {
                    try await queue.exec {
                        try await Task.sleep(nanoseconds: UInt64(5E9))
                    }
                }
                do {
                    try await group.waitForAll()
                } catch {
                    // Cancels barrier tasks
                    group.cancelAll()
                }
                try await queue.exec {
                    try await Task.sleep(nanoseconds: UInt64(5E9))
                }
            }
        }
    }
}

class SafeContinuationTests: XCTestCase {
    typealias IntContinuation = GlobalContinuation<Int, Error>

    func testSafeContinuationMultipleResumeReturningValues() async throws {
        let value = try await IntContinuation.with { continuation in
            let safeContinuation = SafeContinuation(continuation: continuation)
            safeContinuation.resume(returning: 5)
            safeContinuation.resume(returning: 10)
        }
        XCTAssertEqual(value, 5)
    }

    func testSafeContinuationMultipleResumeReturningValueThrowingError()
        async throws
    {
        let value = try await IntContinuation.with { continuation in
            let safeContinuation = SafeContinuation(continuation: continuation)
            safeContinuation.resume(returning: 5)
            safeContinuation.resume(throwing: CancellationError())
        }
        XCTAssertEqual(value, 5)
    }

    func testSafeContinuationMultipleResumeThrowingErrorReturningValue()
        async throws
    {
        do {
            let _ = try await IntContinuation.with { continuation in
                let safeContinuation = SafeContinuation(
                    continuation: continuation
                )
                safeContinuation.resume(throwing: CancellationError())
                safeContinuation.resume(returning: 5)
            }
            XCTFail()
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testSafeContinuationMultipleResumeThrowingErrors() async throws {
        do {
            let _ = try await IntContinuation.with { continuation in
                let safeContinuation = SafeContinuation(
                    continuation: continuation
                )
                safeContinuation.resume(throwing: CancellationError())
                safeContinuation.resume(throwing: URLError(.cancelled))
            }
            XCTFail()
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testSafeContinuationMultipleResultsResumeReturningValues() async throws
    {
        let value = try await IntContinuation.with { continuation in
            let safeContinuation = SafeContinuation(continuation: continuation)
            safeContinuation.resume(with: .success(5))
            safeContinuation.resume(with: .success(10))
        }
        XCTAssertEqual(value, 5)
    }

    func testSafeContinuationMultipleResultsResumeReturningValueThrowingError()
        async throws
    {
        let value = try await IntContinuation.with { continuation in
            let safeContinuation = SafeContinuation(continuation: continuation)
            safeContinuation.resume(with: .success(5))
            safeContinuation.resume(with: .failure(CancellationError()))
        }
        XCTAssertEqual(value, 5)
    }

    func testSafeContinuationMultipleResultsResumeThrowingErrorReturningValue()
        async throws
    {
        do {
            let _ = try await IntContinuation.with { continuation in
                let safeContinuation = SafeContinuation(
                    continuation: continuation
                )
                safeContinuation.resume(with: .failure(CancellationError()))
                safeContinuation.resume(with: .success(5))
            }
            XCTFail()
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }

    func testSafeContinuationMultipleResultsResumeThrowingErrors() async throws
    {
        do {
            let _ = try await IntContinuation.with { continuation in
                let safeContinuation = SafeContinuation(
                    continuation: continuation
                )
                safeContinuation.resume(with: .failure(CancellationError()))
                safeContinuation.resume(with: .failure(URLError(.cancelled)))
            }
            XCTFail()
        } catch {
            XCTAssertTrue(type(of: error) == CancellationError.self)
        }
    }
}
