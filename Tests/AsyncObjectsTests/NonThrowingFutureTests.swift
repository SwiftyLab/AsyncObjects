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
                try! await Task.sleep(nanoseconds: UInt64(5E9))
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
                group.addTask {
                    let value = await allFuture.value
                    XCTAssertEqual(value, [1, 3, 2])
                }
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
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
                group.addTask {
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
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
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
                group.addTask {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.value
                        XCTAssertEqual(value, 1)
                    }
                }
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
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
                group.addTask {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        let value = await allFuture.value
                        XCTAssertEqual(value, 1)
                    }
                }
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    await future2.fulfill(producing: 2)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }
}
