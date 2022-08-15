import XCTest
import Dispatch
@testable import AsyncObjects

class NonThrowingFutureTests: XCTestCase {

    func testFutureFulfilledInitialization() async throws {
        let future = await Future<Int, Never>(with: .success(5))
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
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    let value = await allFuture.value
                    XCTAssertEqual(value, [1, 3, 2])
                }
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
        try await checkExecInterval(durationInSeconds: 3) {
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
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.value
                        XCTAssertEqual(value, 1)
                    }
                }
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
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.value
                        XCTAssertEqual(value, 1)
                    }
                }
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
}
