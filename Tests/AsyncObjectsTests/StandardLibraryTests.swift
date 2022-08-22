import XCTest

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
    static var traceID: Int = 0
    func testTaskLocalVariable() {
        func call() {
            XCTAssertEqual(Self.traceID, 1234)
        }

        XCTAssertEqual(Self.traceID, 0)
        // bind the value
        Self.$traceID.withValue(1234) {
            XCTAssertEqual(Self.traceID, 1234)
            call()

            // unstructured tasks inherit task locals by copying
            Task {
                XCTAssertEqual(Self.traceID, 1234)
            }

            // detached tasks do not inherit task-local values
            Task.detached {
                XCTAssertEqual(Self.traceID, 0)
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
    static var localRef: TaskLocalClass!
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
}
