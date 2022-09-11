import XCTest
@testable import AsyncObjects

/// Tests inner workings of structured concurrency
class StandardLibraryTests: XCTestCase {

    func testTaskValueFetchingCancelation() async throws {
        let task = Task { () -> Int in
            try await Self.sleep(seconds: 1)
            return 5
        }

        let cancellingTask = Task { () -> Int in
            do {
                // Only fails if the task from which value is fetched fails
                // Succeeds even if the current task fails
                let value = try await task.value
                XCTAssertEqual(value, 5)
                return value
            } catch {
                defer { XCTFail("Fetching task value failed") }
                throw error
            }
        }

        cancellingTask.cancel()
        let value = try await task.value
        XCTAssertEqual(value, 5)
    }

    func testAsyncFunctionCallWithoutAwait() async throws {
        let time = DispatchTime.now()
        async let val: Void = Task {
            do {
                try await Self.sleep(seconds: 1)
                print("\(#function): Async task completed")
            } catch {
                XCTFail("Unrecognized task cancellation")
            }
        }.value
        XCTAssertEqual(
            0,
            Int(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / Int(1E9)
        )
        print("\(#function): Test method call completed")
    }

    @TaskLocal
    nonisolated static var traceID: Int = 0
    func testTaskLocalVariable() async {
        func call(_ value: Int) {
            XCTAssertEqual(Self.traceID, value)
        }

        XCTAssertEqual(Self.traceID, 0)
        // bind the value
        await Self.$traceID.withValue(1234) {
            XCTAssertEqual(Self.traceID, 1234)
            call(1234)

            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                XCTAssertEqual(Self.traceID, 1234)
                // Dispatch queue closure execution doesn't
                // inherit task context and task locals
                DispatchQueue.global(qos: .default).async {
                    XCTAssertEqual(Self.traceID, 0)
                    continuation.resume()
                }
            }

            // unstructured tasks inherit task locals by copying
            Task {
                XCTAssertEqual(Self.traceID, 1234)

                Task {
                    XCTAssertEqual(Self.traceID, 1234)
                }
            }

            // detached tasks do not inherit task-local values
            Task.detached {
                XCTAssertEqual(Self.traceID, 0)

                Task {
                    XCTAssertEqual(Self.traceID, 0)
                }
            }

            Self.$traceID.withValue(12345) {
                XCTAssertEqual(Self.traceID, 12345)
                call(12345)

                // unstructured tasks inherit task locals by copying
                Task {
                    XCTAssertEqual(Self.traceID, 12345)

                    Task {
                        XCTAssertEqual(Self.traceID, 12345)
                    }
                }

                // detached tasks do not inherit task-local values
                Task.detached {
                    XCTAssertEqual(Self.traceID, 0)

                    Task {
                        XCTAssertEqual(Self.traceID, 0)
                    }
                }
            }
        }
        XCTAssertEqual(Self.traceID, 0)
    }

    final class TaskLocalClass: Sendable {
        deinit {
            print("[\(Self.self)] Local class deinitialized")
        }
    }

    @TaskLocal
    nonisolated static var localRef: TaskLocalClass!
    func testTaskLocalVariableWithReferenceType() {
        @Sendable
        func call(label: String, fromFunction function: String = #function) {
            print(
                "[\(function)] [\(label)] localRef: \(String(describing: Self.localRef))"
            )
        }

        print("[Initial] localRef: \(String(describing: Self.localRef))")
        XCTAssertNil(Self.localRef)

        Self.$localRef.withValue(TaskLocalClass()) {
            print("[Initial Root] localRef: \(Self.localRef!)")
            call(label: "Root")
            XCTAssertNotNil(Self.localRef)

            Task {
                call(label: "Unstructured")
                XCTAssertNotNil(Self.localRef)
            }

            Task.detached {
                call(label: "Detached")
                XCTAssertNil(Self.localRef)
            }
        }
        call(label: "End")
        XCTAssertNil(Self.localRef)
    }

    func testCancellationHandlerFromAlreadyCancelledTask() async throws {
        let task = Task {
            do {
                try await Self.sleep(seconds: 5)
            } catch {
                await withTaskCancellationHandler {
                    XCTAssertTrue(Task.isCancelled)
                    print("[\(#function)] cancellable operation started")
                } onCancel: {
                    print("[\(#function)] cancellation handler called")
                }
            }
        }
        task.cancel()
        await task.value
    }
}
