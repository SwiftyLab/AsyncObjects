import XCTest
import Dispatch
@testable import AsyncObjects

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

    static func sleep(seconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
    }
}

extension AsyncObject {
    @discardableResult
    @Sendable
    @inlinable
    func wait(forSeconds seconds: UInt64) async -> TaskTimeoutResult {
        return await self.wait(forNanoseconds: seconds * 1_000_000_000)
    }
}
