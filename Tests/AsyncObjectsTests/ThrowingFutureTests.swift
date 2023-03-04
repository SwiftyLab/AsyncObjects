import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
class ThrowingFutureTests: XCTestCase {

    func testFutureFulfilledInitialization() async throws {
        let future = Future<Int, Error>(with: .success(5))
        let value = try await future.wait(forSeconds: 3)
        XCTAssertEqual(value, 5)
    }

    func testFutureFulfillWithSuccess() async throws {
        let future = Future<Int, Error>()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.wait(forSeconds: 3)
                XCTAssertEqual(value, 5)
            }
            group.addTask {
                await future.fulfill(producing: 5)
            }
            try await group.waitForAll()
        }
    }

    func testFutureFulfillWithError() async throws {
        let future = Future<Int, Error>()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let _ = try await future.wait(forSeconds: 3)
                    XCTFail("Unexpected task progression")
                } catch is CancellationError {}
            }
            group.addTask {
                await future.fulfill(throwing: CancellationError())
            }
            try await group.waitForAll()
        }
    }

    func testFutureFulfillWaitCancellation() async throws {
        let future = Future<Int, Error>()
        let waitTask = Task {
            do {
                let _ = try await future.wait(forSeconds: 3)
                XCTFail("Future fulfillments wait not cancelled")
            } catch is CancellationError {}
        }
        waitTask.cancel()
        try await waitTask.value
    }

    func testMultipleTimesFutureFulfilled() async throws {
        let future = Future<Int, Error>(with: .success(5))
        await future.fulfill(producing: 10)
        let value = try await future.wait(forSeconds: 3)
        XCTAssertEqual(value, 5)
    }

    func testDeinit() async throws {
        let future = Future<Int, Error>()
        let task = Task.detached { await future.fulfill(producing: 5) }
        let _ = try await future.wait(forSeconds: 3)
        await task.value
        self.addTeardownBlock { [weak future] in
            try await waitUntil(future, timeout: 5) { $0.assertReleased() }
        }
    }

    func testWaitCancellationWhenTaskCancelled() async throws {
        let future = Future<Int, Error>()
        let task = Task.detached {
            do {
                let _ = try await future.wait(forSeconds: 3)
                XCTFail("Unexpected task progression")
            } catch is CancellationError {}
        }
        task.cancel()
        try await task.value
    }

    func testWaitCancellationForAlreadyCancelledTask() async throws {
        let future = Future<Int, Error>()
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 10)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            do {
                let _ = try await future.wait(forSeconds: 3)
                XCTFail("Unexpected task progression")
            } catch is CancellationError {}
        }
        task.cancel()
        try await task.value
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let future = Future<Int, Error>()
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            let _ = try await future.wait(forSeconds: 3)
                        }
                        group.addTask { await future.fulfill(producing: i) }
                        try await group.waitForAll()
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

@MainActor
class ThrowingFutureCombiningAllTests: XCTestCase {

    func testAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.all(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.wait(forSeconds: 3)
                XCTAssertEqual(value, [1, 2, 3])
            }
            group.addTask { await future1.fulfill(producing: 1) }
            group.addTask { await future2.fulfill(producing: 2) }
            group.addTask { await future3.fulfill(producing: 3) }
            try await group.waitForAll()
        }
    }

    func testSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.all(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let _ = try await future.wait(forSeconds: 3)
                    XCTFail("Future fulfillment did not fail")
                } catch is CancellationError {}
            }
            group.addTask { await future1.fulfill(producing: 1) }
            group.addTask {
                await future2.fulfill(throwing: CancellationError())
            }
            group.addTask { await future3.fulfill(producing: 3) }
            try await group.waitForAll()
        }
    }

    func testEmptyConstructing() async throws {
        let future = Future<Int, Error>.all()
        let value = try await future.wait(forSeconds: 3)
        XCTAssertTrue(value.isEmpty)
    }
}

@MainActor
class ThrowingFutureCombiningAllSettledTests: XCTestCase {

    func testAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.allSettled(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let values = try await future.wait(forSeconds: 3)
                for (index, item) in values.enumerated() {
                    switch item {
                    case .success(let value):
                        XCTAssertEqual(value, index + 1)
                    default:
                        XCTFail("Unexpected future fulfillment")
                    }
                }
            }
            await future1.fulfill(producing: 1)
            await future2.fulfill(producing: 2)
            await future3.fulfill(producing: 3)
            try await group.waitForAll()
        }
    }

    func testSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.allSettled(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let values = try await future.wait(forSeconds: 3)
                for (index, item) in values.enumerated() {
                    switch item {
                    case .success(let value):
                        XCTAssertEqual(value, index + 1)
                    case .failure(is CancellationError):
                        XCTAssertEqual(index + 1, 2)
                    default:
                        XCTFail("Unexpected future fulfillment")
                    }
                }
            }
            await future1.fulfill(producing: 1)
            await future2.fulfill(throwing: CancellationError())
            await future3.fulfill(producing: 3)
            try await group.waitForAll()
        }
    }

    func testEmptyConstructing() async throws {
        let future = Future<Int, Error>.allSettled()
        let value = try await future.wait(forSeconds: 3)
        XCTAssertTrue(value.isEmpty)
    }
}

@MainActor
class ThrowingFutureRacingTests: XCTestCase {

    func testAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.race(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.wait(forSeconds: 3)
                XCTAssertEqual(value, 1)
            }
            await future1.fulfill(producing: 1)
            try await waitUntil(future, timeout: 5) { $0.result != nil }
            await future2.fulfill(producing: 2)
            await future3.fulfill(producing: 3)
            try await group.waitForAll()
        }
    }

    func testSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.race(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let _ = try await future.wait(forSeconds: 3)
                    XCTFail("Future fulfillment did not fail")
                } catch is CancellationError {}
            }
            await future1.fulfill(throwing: CancellationError())
            try await waitUntil(future, timeout: 5) { $0.result != nil }
            await future2.fulfill(producing: 2)
            await future3.fulfill(producing: 3)
            try await group.waitForAll()
        }
    }
}

@MainActor
class ThrowingFutureSelectAnyTests: XCTestCase {

    func testAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.any(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.wait(forSeconds: 3)
                XCTAssertEqual(value, 1)
            }
            await future1.fulfill(producing: 1)
            try await waitUntil(future, timeout: 5) { $0.result != nil }
            await future2.fulfill(producing: 2)
            await future3.fulfill(producing: 3)
            try await group.waitForAll()
        }
    }

    func testSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.any(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.wait(forSeconds: 3)
                XCTAssertEqual(value, 2)
            }
            await future1.fulfill(throwing: CancellationError())
            await future2.fulfill(producing: 2)
            try await waitUntil(future, timeout: 5) { $0.result != nil }
            await future3.fulfill(producing: 3)
            try await group.waitForAll()
        }
    }

    func testAllErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let future = Future.any(future1, future2, future3)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let _ = try await future.wait(forSeconds: 3)
                    XCTFail("Future fulfillment did not fail")
                } catch is CancellationError {}
            }
            group.addTask {
                await future1.fulfill(throwing: CancellationError())
            }
            group.addTask {
                await future2.fulfill(throwing: CancellationError())
            }
            group.addTask {
                await future3.fulfill(throwing: CancellationError())
            }
            try await group.waitForAll()
        }
    }

    func testEmptyConstructing() async {
        let future = Future<Int, Error>.any()
        let result = await future.result
        switch result {
        case .failure(is CancellationError): break
        default: XCTFail("Unexpected future fulfillment")
        }
    }
}

extension Future where Failure == Error {
    @Sendable
    @inlinable
    func wait(forSeconds seconds: UInt64) async throws -> Output {
        return try await waitForTaskCompletion(
            withTimeoutInNanoseconds: seconds * 1_000_000_000
        ) {
            return try await self.get()
        }
    }
}
