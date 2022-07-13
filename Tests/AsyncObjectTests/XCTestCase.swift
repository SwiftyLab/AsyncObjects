import XCTest
import Dispatch

extension XCTestCase {
    func checkExecInterval(
        for task: () async throws -> Void,
        durationInSeconds seconds: Int = 0
    ) async rethrows {
        let time = DispatchTime.now()
        try await task()
        XCTAssertEqual(
            seconds,
            Int(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / Int(1E9)
        )
    }
}
