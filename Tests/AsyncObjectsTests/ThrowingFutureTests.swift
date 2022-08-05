import XCTest
import Dispatch
@testable import AsyncObjects

class ThrowingFutureTests: XCTestCase {

    func testFutureFulfilledInitialization() async throws {
        let future = await Future<Int, Error>(with: .success(5))
        let value = try await future.value
        XCTAssertEqual(value, 5)
    }

    func testFutureFulfillWithSuccess() async throws {
        let future = Future<Int, Error>()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.value
                XCTAssertEqual(value, 5)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(5E9))
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
                    let _ = try await future.value
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(5E9))
                await future.fulfill(throwing: CancellationError())
            }
            try await group.waitForAll()
        }
    }

    func testFutureFulfillWaitCancellation() async throws {
        let future = Future<Int, Error>()
        let waitTask = Task {
            do {
                let _ = try await future.value
                XCTFail("Future fulfillments wait not cancelled")
            } catch {
                XCTAssertTrue(type(of: error) == CancellationError.self)
            }
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(3E9))
                waitTask.cancel()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(5E9))
                await future.fulfill(producing: 5)
            }
            try await group.waitForAll()
        }
    }

    func testCombiningAllPromisesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.all(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let value = try await allFuture.value
                    XCTAssertEqual(value, [1, 2, 3])
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

    func testCombiningAllPromisesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.all(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.checkExecInterval(durationInSeconds: 2) {
                        do {
                            let _ = try await allFuture.value
                            XCTFail("Future fulfillment did not fail")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
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
                    await future2.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testCombiningAllSettledPromisesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
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

    func testCombiningAllSettledPromisesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.allSettled(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.checkExecInterval(durationInSeconds: 3) {
                        let values = await allFuture.value
                        for (index, item) in values.enumerated() {
                            switch item {
                            case .success(let value):
                                XCTAssertEqual(value, index + 1)
                            case .failure(let error):
                                XCTAssertTrue(
                                    type(of: error) == CancellationError.self
                                )
                                XCTAssertEqual(index + 1, 2)
                            }
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
                    await future2.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testRacingPromisesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.race(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.checkExecInterval(durationInSeconds: 1) {
                        let value = try await allFuture.value
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

    func testRacingPromisesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.race(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.checkExecInterval(durationInSeconds: 1) {
                        do {
                            let _ = try await allFuture.value
                            XCTFail("Future fulfillment did not fail")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(throwing: CancellationError())
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

    func testAnyPromisesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.any(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.checkExecInterval(durationInSeconds: 1) {
                        let value = try await allFuture.value
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

    func testAnyPromisesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.any(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.checkExecInterval(durationInSeconds: 2) {
                        let value = try await allFuture.value
                        XCTAssertEqual(value, 2)
                    }
                }
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(throwing: CancellationError())
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

    func testAnyPromisesWithAllErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = await Future.any(future1, future2, future3)
        try await checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.checkExecInterval(durationInSeconds: 3) {
                        do {
                            let _ = try await allFuture.value
                            XCTFail("Future fulfillment did not fail")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                // To make sure all future task started
                // before adding future fulfill tasks
                try await Task.sleep(nanoseconds: UInt64(1E7))
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(1E9))
                    await future1.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(2E9))
                    await future2.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(3E9))
                    await future3.fulfill(throwing: CancellationError())
                }
                try await group.waitForAll()
            }
        }
    }
}
