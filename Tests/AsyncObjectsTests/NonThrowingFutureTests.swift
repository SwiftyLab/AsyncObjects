import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
class NonThrowingFutureTests: XCTestCase {

    func testFulfilledInitialization() async throws {
        let future = Future<Int, Never>(with: .success(5))
        let value = try await future.wait(forSeconds: 3)
        XCTAssertEqual(value, 5)
    }

    func testFulfillAfterInitialization() async throws {
        let future = Future<Int, Never>()
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

    func testFulfilledWithAttemptClosure() async throws {
        let future = Future<Int, Never> { promise in
            DispatchQueue.global(qos: .background)
                .asyncAfter(deadline: .now() + 0.5) {
                    promise(.success(5))
                }
        }
        let value = try await future.wait(forSeconds: 5)
        XCTAssertEqual(value, 5)
    }

    func testMultipleTimesFutureFulfilled() async throws {
        let future = Future<Int, Never>(with: .success(5))
        await future.fulfill(producing: 10)
        let value = try await future.wait(forSeconds: 3)
        XCTAssertEqual(value, 5)
    }

    func testAsyncInitializerDuration() async throws {
        let future = Future<Int, Never> { promise in
            try! await Task.sleep(seconds: 2)
            promise(.success(5))
        }
        let value = try await future.wait(forSeconds: 5)
        XCTAssertEqual(value, 5)
    }

    func testDeinit() async throws {
        let future = Future<Int, Never>()
        let task = Task.detached { await future.fulfill(producing: 5) }
        let _ = try await future.wait(forSeconds: 3)
        await task.value
        self.addTeardownBlock { [weak future] in
            try await waitUntil(future, timeout: 5) { $0.assertReleased() }
        }
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let future = Future<Int, Never>()
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
class NonThrowingFutureCombiningTests: XCTestCase {

    func testAllPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
        let future = Future.all(future1, future3, future2)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.wait(forSeconds: 3)
                XCTAssertEqual(value, [1, 3, 2])
            }
            group.addTask { await future1.fulfill(producing: 1) }
            group.addTask { await future2.fulfill(producing: 2) }
            group.addTask { await future3.fulfill(producing: 3) }
            try await group.waitForAll()
        }
    }

    func testAllSettledPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
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

    func testRacingPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
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

    func testAnyPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
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

    func testConstructingAllFutureFromEmpty() async throws {
        let future = Future<Int, Never>.all()
        let value = try await future.wait(forSeconds: 3)
        XCTAssertTrue(value.isEmpty)
    }

    func testConstructingAllSettledFutureFromEmpty() async throws {
        let future = Future<Int, Never>.allSettled()
        let value = try await future.wait(forSeconds: 3)
        XCTAssertTrue(value.isEmpty)
    }
}

extension Future where Failure == Never {
    @Sendable
    @inlinable
    func wait(forSeconds seconds: UInt64) async throws -> Output {
        return try await waitForTaskCompletion(
            withTimeoutInNanoseconds: seconds * 1_000_000_000
        ) {
            return await self.get()
        }
    }
}
