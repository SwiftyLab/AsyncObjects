import XCTest
@testable import AsyncObjects

@MainActor
class SafeContinuationTests: XCTestCase {

    func testResumingWithInitializedStatusWaiting() async throws {
        let value = await GlobalContinuation<Int, Never>.with { c in
            let safe = SafeContinuation(status: .waiting, with: c)
            XCTAssertFalse(safe.resumed)
            safe.resume(returning: 3)
            XCTAssertTrue(safe.resumed)
        }
        XCTAssertEqual(value, 3)
    }

    func testResumingWithInitializedStatusResuming() async throws {
        let value = await GlobalContinuation<Int, Never>.with { c in
            let safe = SafeContinuation(
                status: .willResume(.success(5)),
                with: c
            )
            XCTAssertTrue(safe.resumed)
            safe.resume(returning: 3)
        }
        XCTAssertEqual(value, 5)
    }

    func testResumingWithInitializedStatusResumed() async throws {
        let value = try await GlobalContinuation<Int, Error>.with { c in
            c.resume(returning: 3)
            let safe = SafeContinuation(status: .resumed, with: c)
            XCTAssertTrue(safe.resumed)
            safe.resume(throwing: CancellationError())
        }
        XCTAssertEqual(value, 3)
    }

    func testDirectResumeWithSuccess() async throws {
        await Self.checkExecInterval(durationInSeconds: 0) {
            await SafeContinuation<GlobalContinuation<Void, Never>>.with { c in
                XCTAssertFalse(c.resumed)
                c.resume()
                XCTAssertTrue(c.resumed)
            }
        }
    }

    func testDirectResumeWithError() async throws {
        typealias C = GlobalContinuation<Void, Error>
        await Self.checkExecInterval(durationInSeconds: 0) {
            do {
                try await SafeContinuation<C>.with { c in
                    XCTAssertFalse(c.resumed)
                    c.resume(throwing: CancellationError())
                    XCTAssertTrue(c.resumed)
                }
                XCTFail("Unexpected task progression")
            } catch {
                XCTAssertTrue(type(of: error) == CancellationError.self)
            }
        }
    }

    func testInitializedWithoutContinuationWithStatusWaiting() async throws {
        typealias C = GlobalContinuation<Int, Never>
        let value = await C.with { c in
            let safe = SafeContinuation<C>(status: .waiting)
            XCTAssertFalse(safe.resumed)
            safe.resume(returning: 3)
            XCTAssertTrue(safe.resumed)
            safe.add(continuation: c)
        }
        XCTAssertEqual(value, 3)
    }

    func testInitializedWithoutContinuationWithStatusResuming() async throws {
        typealias C = GlobalContinuation<Int, Never>
        let value = await C.with { c in
            let safe = SafeContinuation<C>(status: .willResume(.success(5)))
            XCTAssertTrue(safe.resumed)
            safe.resume(returning: 3)
            safe.add(continuation: c)
        }
        XCTAssertEqual(value, 5)
    }

    func testStatusUpdateFromWaitingToResuming() async throws {
        typealias C = GlobalContinuation<Int, Never>
        let value = await C.with { c in
            let safe = SafeContinuation<C>(status: .waiting)
            XCTAssertFalse(safe.resumed)
            safe.add(continuation: c, status: .willResume(.success(5)))
            XCTAssertTrue(safe.resumed)
        }
        XCTAssertEqual(value, 5)
    }

    func testStatusUpdateFromWaitingToResumed() async throws {
        typealias C = GlobalContinuation<Int, Never>
        let value = await C.with { c in
            let safe = SafeContinuation<C>(status: .waiting)
            XCTAssertFalse(safe.resumed)
            c.resume(returning: 5)
            safe.add(continuation: c, status: .resumed)
            XCTAssertTrue(safe.resumed)
        }
        XCTAssertEqual(value, 5)
    }

    func testStatusUpdateFromResumedToWaiting() async throws {
        typealias C = GlobalContinuation<Int, Never>
        let value = await C.with { c in
            c.resume(returning: 5)
            let safe = SafeContinuation<C>(status: .resumed)
            XCTAssertTrue(safe.resumed)
            safe.add(continuation: c, status: .waiting)
            XCTAssertTrue(safe.resumed)
        }
        XCTAssertEqual(value, 5)
    }

    func testCancellationHandlerWhenTaskCancelled() async throws {
        typealias C = GlobalContinuation<Void, Error>
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await SafeContinuation<C>.withCancellation {
                        // Do nothing
                    } operation: { _ in
                        // Do nothing
                    }
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
            }
        }
        task.cancel()
        await task.value
    }

    func testCancellationHandlerForAlreadyCancelledTask() async throws {
        typealias C = GlobalContinuation<Void, Error>
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 0) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                do {
                    try await SafeContinuation<C>.withCancellation {
                    } operation: { _ in
                    }
                    XCTFail("Unexpected task progression")
                } catch {
                    XCTAssertTrue(type(of: error) == CancellationError.self)
                }
            }
        }
        task.cancel()
        await task.value
    }

    func testNonCancellableContinuation() async throws {
        typealias C = GlobalContinuation<Void, Never>
        let task = Task.detached {
            await Self.checkExecInterval(durationInSeconds: 1) {
                do {
                    try await Self.sleep(seconds: 5)
                    XCTFail("Unexpected task progression")
                } catch {}
                XCTAssertTrue(Task.isCancelled)
                await SafeContinuation<C>.withCancellation {
                } operation: { continuation in
                    Task {
                        defer { continuation.resume() }
                        try await Self.sleep(seconds: 1)
                    }
                }
            }
        }
        task.cancel()
        await task.value
    }
}
