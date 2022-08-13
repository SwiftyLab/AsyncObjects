import XCTest

/// Tests inner workings of structured concurrency
class StandardLibraryTests: XCTestCase {

    func testTaskValueFetchingCancelation() async throws {
        let task = Task { () -> Int in
            try await Task.sleep(nanoseconds: UInt64(3E9))
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
                try await Task.sleep(nanoseconds: UInt64(3E9))
                debugPrint("\(#function): Async task completed")
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
        debugPrint("\(#function): Test method call completed")
    }
}
