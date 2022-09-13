import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
class ThrowingFutureTests: XCTestCase {

    func testFutureFulfilledInitialization() async throws {
        let future = Future<Int, Error>(with: .success(5))
        let value = try await future.get()
        XCTAssertEqual(value, 5)
    }

    func testFutureFulfillWithSuccess() async throws {
        let future = Future<Int, Error>()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let value = try await future.get()
                XCTAssertEqual(value, 5)
            }
            group.addTask {
                try await Self.sleep(seconds: 1)
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
                    let _ = try await future.get()
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
            }
            group.addTask {
                try await Self.sleep(seconds: 1)
                await future.fulfill(throwing: CancellationError())
            }
            try await group.waitForAll()
        }
    }

    func testFutureFulfillWaitCancellation() async throws {
        let future = Future<Int, Error>()
        let waitTask = Task {
            do {
                let _ = try await future.get()
                XCTFail("Future fulfillments wait not cancelled")
            } catch {
                XCTAssertTrue(type(of: error) == CancellationError.self)
            }
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Self.sleep(seconds: 1)
                waitTask.cancel()
            }
            group.addTask {
                try await Self.sleep(seconds: 2)
                await future.fulfill(producing: 5)
            }
            try await group.waitForAll()
        }
    }

    func testCombiningAllFuturesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.all(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    let value = try await allFuture.get()
                    XCTAssertEqual(value, [1, 2, 3])
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
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

    func testCombiningAllFuturesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.all(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await Self.checkExecInterval(durationInSeconds: 2) {
                        do {
                            let _ = try await allFuture.get()
                            XCTFail("Future fulfillment did not fail")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testCombiningAllSettledFuturesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.allSettled(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
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
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
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

    func testCombiningAllSettledFuturesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.allSettled(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await Self.checkExecInterval(durationInSeconds: 3) {
                        let values = await allFuture.get()
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
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(producing: 1)
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
                    await future3.fulfill(producing: 3)
                }
                try await group.waitForAll()
            }
        }
    }

    func testRacingFuturesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.race(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.checkExecInterval(durationInSeconds: 1) {
                        let value = try await allFuture.get()
                        XCTAssertEqual(value, 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
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

    func testRacingFuturesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.race(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await Self.checkExecInterval(durationInSeconds: 1) {
                        do {
                            let _ = try await allFuture.get()
                            XCTFail("Future fulfillment did not fail")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(throwing: CancellationError())
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

    func testAnyFuturesWithAllSuccess() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.any(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.checkExecInterval(durationInSeconds: 1) {
                        let value = try await allFuture.get()
                        XCTAssertEqual(value, 1)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
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

    func testAnyFuturesWithSomeErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.any(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    try await Self.checkExecInterval(durationInSeconds: 2) {
                        let value = try await allFuture.get()
                        XCTAssertEqual(value, 2)
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(throwing: CancellationError())
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

    func testAnyFuturesWithAllErrors() async throws {
        let future1 = Future<Int, Error>()
        let future2 = Future<Int, Error>()
        let future3 = Future<Int, Error>()
        let allFuture = Future.any(future1, future2, future3)
        try await Self.checkExecInterval(durationInSeconds: 3) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                await group.addTaskAndStart {
                    await Self.checkExecInterval(durationInSeconds: 3) {
                        do {
                            let _ = try await allFuture.get()
                            XCTFail("Future fulfillment did not fail")
                        } catch {
                            XCTAssertTrue(
                                type(of: error) == CancellationError.self
                            )
                        }
                    }
                }
                // Make sure previous tasks started
                try await Self.sleep(seconds: 0.01)
                group.addTask {
                    try await Self.sleep(seconds: 1)
                    await future1.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Self.sleep(seconds: 2)
                    await future2.fulfill(throwing: CancellationError())
                }
                group.addTask {
                    try await Self.sleep(seconds: 3)
                    await future3.fulfill(throwing: CancellationError())
                }
                try await group.waitForAll()
            }
        }
    }

    func testConstructingAnyFutureFromZeroFutures() async {
        let future = Future<Int, Error>.any()
        let result = await future.result
        switch result {
        case .failure(let error):
            XCTAssertTrue(type(of: error) == CancellationError.self)
        default: XCTFail("Unexpected future fulfillment")
        }
    }

    func testConstructingAllFutureFromZeroFutures() async throws {
        let future = Future<Int, Error>.all()
        let value = try await future.get()
        XCTAssertTrue(value.isEmpty)
    }

    func testConstructingAllSettledFutureFromZeroFutures() async throws {
        let future = Future<Int, Error>.allSettled()
        let value = await future.get()
        XCTAssertTrue(value.isEmpty)
    }

    func testMultipleTimesFutureFulfilled() async throws {
        let future = Future<Int, Error>(with: .success(5))
        await future.fulfill(producing: 10)
        let value = try await future.get()
        XCTAssertEqual(value, 5)
    }

    func testDeinit() async throws {
        let future = Future<Int, Error>()
        Task.detached {
            try await Self.sleep(seconds: 1)
            await future.fulfill(producing: 5)
        }
        let _ = try await future.get()
        self.addTeardownBlock { [weak future] in
            try await Self.sleep(seconds: 1)
            XCTAssertNil(future)
        }
    }

    func testWaitCancellationWhenTaskCancelled() async throws {
        let future = Future<Int, Error>()
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    let _ = try await future.get()
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
            }
        }
        task.cancel()
        await task.value
    }

    func testWaitCancellationForAlreadyCancelledTask() async throws {
        let future = Future<Int, Error>()
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                do {
                    let _ = try await future.get()
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
            }
        }
        task.cancel()
        await task.value
    }

    func testConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let future = Future<Int, Error>()
                    try await Self.checkExecInterval(durationInSeconds: 0) {
                        try await withThrowingTaskGroup(of: Void.self) {
                            group in
                            group.addTask { let _ = try await future.get() }
                            group.addTask { await future.fulfill(producing: i) }
                            try await group.waitForAll()
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}
