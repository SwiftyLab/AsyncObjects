import XCTest
@testable import AsyncObjects

@MainActor
class TrackedContinuationTests: XCTestCase {

    func testResumingWithInitializedStatusWaiting() async throws {
        let value = await GlobalContinuation<Int, Never>.with { c in
            let safe = TrackedContinuation(with: c)
            XCTAssertFalse(safe.resumed)
            safe.resume(returning: 3)
            XCTAssertTrue(safe.resumed)
        }
        XCTAssertEqual(value, 3)
    }

    func testDirectResumeWithSuccess() async throws {
        await TrackedContinuation<GlobalContinuation<Void, Never>>.with {
            XCTAssertFalse($0.resumed)
            $0.resume()
            XCTAssertTrue($0.resumed)
        }
    }

    func testDirectResumeWithError() async throws {
        typealias C = GlobalContinuation<Void, Error>
        do {
            try await TrackedContinuation<C>.with { c in
                XCTAssertFalse(c.resumed)
                c.resume(throwing: CancellationError())
                XCTAssertTrue(c.resumed)
            }
            XCTFail("Unexpected task progression")
        } catch is CancellationError {}
    }

    func testInitializedWithoutContinuationWithStatusWaiting() async throws {
        typealias C = GlobalContinuation<Int, Never>
        let value = await C.with { c in
            let safe = TrackedContinuation<C>()
            XCTAssertFalse(safe.resumed)
            safe.resume(returning: 3)
            XCTAssertTrue(safe.resumed)
            safe.add(continuation: c)
        }
        XCTAssertEqual(value, 3)
    }

    func testCancellationHandlerWhenTaskCancelled() async throws {
        typealias C = GlobalContinuation<Void, Error>
        let task = Task.detached {
            do {
                try await TrackedContinuation<C>
                    .withCancellation(id: .init()) {
                        $0.cancel()
                    } operation: { _, preinit in
                        preinit()
                    }
                XCTFail("Unexpected task progression")
            } catch is CancellationError {}
        }
        task.cancel()
        try await task.value
    }

    func testCancellationHandlerForAlreadyCancelledTask() async throws {
        typealias C = GlobalContinuation<Void, Error>
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 5)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            do {
                try await TrackedContinuation<C>
                    .withCancellation(id: .init()) {
                        $0.cancel()
                    } operation: { _, preinit in
                        preinit()
                    }
                XCTFail("Unexpected task progression")
            } catch is CancellationError {}
        }
        task.cancel()
        try await task.value
    }

    func testNonCancellableContinuation() async throws {
        typealias C = GlobalContinuation<Void, Never>
        let task = Task.detached {
            do {
                try await Task.sleep(seconds: 5)
                XCTFail("Unexpected task progression")
            } catch {}
            XCTAssertTrue(Task.isCancelled)
            await TrackedContinuation<C>
                .withCancellation(id: .init()) { _ in
                    // Do nothing
                } operation: { continuation, preinit in
                    preinit()
                    Task {
                        defer { continuation.resume() }
                        try await Task.sleep(seconds: 1)
                    }
                }
        }
        task.cancel()
        await task.value
    }
}
