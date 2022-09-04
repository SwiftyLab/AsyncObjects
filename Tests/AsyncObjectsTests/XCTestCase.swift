import XCTest
import Dispatch
@testable import AsyncObjects

@MainActor
extension XCTestCase {
    private static var activitySupported = ProcessInfo.processInfo.environment
        .keys.contains("__XCODE_BUILT_PRODUCTS_DIR_PATHS")

    private static func runAssertions(
        with name: String?,
        _ assertions: () -> Void
    ) {
        #if canImport(Darwin)
        if let name = name, activitySupported {
            XCTContext.runActivity(named: name) { activity in
                assertions()
            }
        } else {
            assertions()
        }
        #else
        assertions()
        #endif
    }

    static func checkExecInterval(
        name: String? = nil,
        durationInSeconds seconds: Int = 0,
        for task: () async throws -> Void
    ) async rethrows {
        let time = DispatchTime.now()
        try await task()
        let assertions = {
            XCTAssertEqual(
                seconds,
                Int(
                    (Double(
                        DispatchTime.now().uptimeNanoseconds
                            - time.uptimeNanoseconds
                    ) / 1E9).rounded(.toNearestOrAwayFromZero)
                )
            )
        }
        runAssertions(with: name, assertions)
    }

    static func checkExecInterval(
        name: String? = nil,
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
        let assertions = {
            XCTAssertEqual(
                seconds,
                (duration / 1E9).rounded() / order
            )
        }
        runAssertions(with: name, assertions)
    }

    static func checkExecInterval<R: RangeExpression>(
        name: String? = nil,
        durationInRange range: R,
        for task: () async throws -> Void
    ) async rethrows where R.Bound == Int {
        let time = DispatchTime.now()
        try await task()
        let duration = Int(
            (Double(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / 1E9).rounded(.toNearestOrAwayFromZero)
        )
        let assertions = {
            XCTAssertTrue(
                range.contains(duration),
                "\(duration) not present in \(range)"
            )
        }
        runAssertions(with: name, assertions)
    }

    static func checkExecInterval<R: RangeExpression>(
        name: String? = nil,
        durationInRange range: R,
        for task: () async throws -> Void
    ) async rethrows where R.Bound == Double {
        let time = DispatchTime.now()
        try await task()
        let duration =
            Double(
                DispatchTime.now().uptimeNanoseconds - time.uptimeNanoseconds
            ) / 1E9
        let assertions = {
            XCTAssertTrue(
                range.contains(duration),
                "\(duration) not present in \(range)"
            )
        }
        runAssertions(with: name, assertions)
    }

    static func sleep(seconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
    }

    static func sleep(forSeconds seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1E9))
    }
}

extension AsyncObject {
    @Sendable
    @inlinable
    func wait(forSeconds seconds: UInt64) async throws {
        return try await self.wait(forNanoseconds: seconds * 1_000_000_000)
    }
}
