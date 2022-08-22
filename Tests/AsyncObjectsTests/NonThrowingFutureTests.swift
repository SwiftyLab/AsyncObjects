import XCTest
import Dispatch
@testable import AsyncObjects

class NonThrowingFutureTests: XCTestCase {

    func testFutureFulfilledInitialization() async throws {
        let future = Future<Int, Never>(with: .success(5))
        let value = await future.value
        XCTAssertEqual(value, 5)
    }

    func testFutureFulfillAfterInitialization() async throws {
        let future = Future<Int, Never>()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = await future.value
                XCTAssertEqual(value, 5)
            }
            group.addTask {
                try! await Self.sleep(seconds: 1)
                await future.fulfill(producing: 5)
            }
            await group.waitForAll()
        }
    }

    func testFutureFulfilledWithAttemptClosure() async throws {
        let future = await Future<Int, Never> { promise in
            DispatchQueue.global(qos: .background)
                .asyncAfter(deadline: .now() + 2) {
                    promise(.success(5))
                }
        }
        let value = await future.value
        XCTAssertEqual(value, 5)
    }

    func testCombiningAllPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
        let allFuture = await Future.all(future1, future3, future2)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    let value = await allFuture.value
                    XCTAssertEqual(value, [1, 3, 2])
                }
                // Make sure previous tasks started
                try await Self.sleep(forSeconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testCombiningAllSettledPromises() async throws {
        let future1 = Future<Int, Never>()
        let future2 = Future<Int, Never>()
        let future3 = Future<Int, Never>()
        let allFuture = await Future.allSettled(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    let values = await allFuture.value
                    for (index, item) in values.enumerated() {
                        switch item {
                        case .success(let value):
                            XCTAssertEqual(value, index + 1)
                        default:
                            XCTFail("Unexpected future fulfillment")
                        }
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(forSeconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
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
        let allFuture = await Future.race(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await Self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.value
                        XCTAssertEqual(value, 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(forSeconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
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
        let allFuture = await Future.any(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await Self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.value
                        XCTAssertEqual(value, 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(forSeconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testConstructingAllFutureFromZeroFutures() async {
        let future = await Future<Int, Never>.all()
        let value = await future.value
        XCTAssertTrue(value.isEmpty)
    }

    func testConstructingAllSettledFutureFromZeroFutures() async {
        let future = await Future<Int, Never>.allSettled()
        let value = await future.value
        XCTAssertTrue(value.isEmpty)
    }

    func testMultipleTimesFutureFulfilled() async throws {
        let future = Future<Int, Never>(with: .success(5))
        await future.fulfill(producing: 10)
        let value = await future.value
        XCTAssertEqual(value, 5)
    }

    func testFutureAsyncInitializerDuration() async throws {
        await Self.checkExecInterval(durationInSeconds: 0) {
            let _ = await Future<Int, Never> { promise in
                try! await Self.sleep(seconds: 1)
                promise(.success(5))
            }
        }
    }
}
