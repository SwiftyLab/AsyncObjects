import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
class NonThrowingFutureTests: XCTestCase {

    func testFutureFulfilledInitialization() async throws {
        let future = Future<Int, Never>(with: .success(5))
        let value = await future.get()
        XCTAssertEqual(value, 5)
    }

    func testFutureFulfillAfterInitialization() async throws {
        let future = Future<Int, Never>()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = await future.get()
                XCTAssertEqual(value, 5)
            }
            group.addTask {
                try! await self.sleep(seconds: 1)
                await future.fulfill(producing: 5)
            }
            await group.waitForAll()
        }
    }

    func testFutureFulfilledWithAttemptClosure() async throws {
        let future = Future<Int, Never> { promise in
            DispatchQueue.global(qos: .background)
                .asyncAfter(deadline: .now() + 2) {
                    promise(.success(5))
                }
        }
        let value = await future.get()
        XCTAssertEqual(value, 5)
    }

    func testMultipleTimesFutureFulfilled() async throws {
        let future = Future<Int, Never>(with: .success(5))
        await future.fulfill(producing: 10)
        let value = await future.get()
        XCTAssertEqual(value, 5)
    }

    func testFutureAsyncInitializerDuration() async throws {
        await self.checkExecInterval(durationInSeconds: 0) {
            let _ = Future<Int, Never> { promise in
                try! await self.sleep(seconds: 1)
                promise(.success(5))
            }
        }
    }

    func testDeinit() async throws {
        let future = Future<Int, Never>()
        Task.detached {
            try await self.sleep(seconds: 1)
            await future.fulfill(producing: 5)
        }
        let _ = await future.get()
        self.addTeardownBlock { [weak future] in
            try await self.sleep(seconds: 1)
            XCTAssertNil(future)
        }
    }

    func testConcurrentAccess() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let future = Future<Int, Never>()
                    await self.checkExecInterval(durationInSeconds: 0) {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { let _ = await future.get() }
                            group.addTask { await future.fulfill(producing: i) }
                            await group.waitForAll()
                        }
                    }
                }
                await group.waitForAll()
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
        let allFuture = Future.all(future1, future3, future2)
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    let value = await allFuture.get()
                    XCTAssertEqual(value, [1, 3, 2])
                }
                group.addTask {
                    try await self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testAllSettledPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
        let allFuture = Future.allSettled(future1, future2, future3)
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    let values = await allFuture.get()
                    for (index, item) in values.enumerated() {
                        switch item {
                        case .success(let value):
                            XCTAssertEqual(value, index + 1)
                        default:
                            XCTFail("Unexpected future fulfillment")
                        }
                    }
                }
                group.addTask {
                    try await self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testRacingPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
        let allFuture = Future.race(future1, future2, future3)
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.get()
                        XCTAssertEqual(value, 1)
                    }
                }
                group.addTask {
                    try await self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testAnyPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
        let allFuture = Future.any(future1, future2, future3)
        try await self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.get()
                        XCTAssertEqual(value, 1)
                    }
                }
                group.addTask {
                    try await self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testConstructingAllFutureFromEmpty() async {
        let future = Future<Int, Never>.all()
        let value = await future.get()
        XCTAssertTrue(value.isEmpty)
    }

    func testConstructingAllSettledFutureFromEmpty() async {
        let future = Future<Int, Never>.allSettled()
        let value = await future.get()
        XCTAssertTrue(value.isEmpty)
    }
}
