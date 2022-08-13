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

    func checkExecInterval(
        durationInSeconds seconds: Double = 0,
        roundedUpTo digit: UInt = 1,
        for task: () async throws -> Void
    ) async rethrows {
        let time = DispatchTime.now()
        try await task()
        let order = pow(10, Double(digit))
        let duration =
            Double(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) * order
        XCTAssertEqual(
            seconds,
            (duration / 1E9).rounded() / order
        )
    }

    func checkExecInterval<R: RangeExpression>(
        durationInRange range: R,
        for task: () async throws -> Void
    ) async rethrows where R.Bound == Int {
        let time = DispatchTime.now()
        try await task()
        let duration =
            Int(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / Int(1E9)
        XCTAssertTrue(
            range.contains(duration),
            "\(duration) not present in \(range)"
        )
    }

    func checkExecInterval<R: RangeExpression>(
        durationInRange range: R,
        for task: () async throws -> Void
    ) async rethrows where R.Bound == Double {
        let time = DispatchTime.now()
        try await task()
        let duration =
            Double(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / 1E9
        XCTAssertTrue(
            range.contains(duration),
            "\(duration) not present in \(range)"
        )
    }
}
