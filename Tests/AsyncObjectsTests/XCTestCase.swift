import XCTest
import Dispatch

extension XCTestCase {
    func checkExecInterval(
        durationInSeconds seconds: Int = 0,
        for task: () async throws -> Void
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

    func checkExecInterval<R: RangeExpression>(
        durationInRange range: R,
        for task: () async throws -> Void
    ) async rethrows where R.Bound == Int {
        let time = DispatchTime.now()
        try await task()
        XCTAssertTrue(
            range.contains(
                Int(
                    DispatchTime.now().uptimeNanoseconds
                        - time.uptimeNanoseconds
                ) / Int(1E9)
            )
        )
    }
}
