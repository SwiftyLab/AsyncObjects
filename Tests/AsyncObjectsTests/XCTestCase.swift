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

    static func checkExecInterval<T: DivisiveArithmetic>(
        name: String? = nil,
        durationInSeconds seconds: T = .zero,
        for task: () async throws -> Void
    ) async rethrows where T: Comparable {
        let second: T = 1_000_000_000
        let time = DispatchTime.now().uptimeNanoseconds
        try await task()
        guard
            let span = T(exactly: DispatchTime.now().uptimeNanoseconds - time),
            case let duration = span / second
        else { XCTFail("Invalid number type: \(T.self)"); return }
        let assertions = {
            XCTAssertLessThanOrEqual(duration, seconds + 1)
            XCTAssertGreaterThanOrEqual(duration, seconds - 1)
        }
        runAssertions(with: name, assertions)
    }

    static func checkExecInterval<R: RangeExpression>(
        name: String? = nil,
        durationInRange range: R,
        for task: () async throws -> Void
    ) async rethrows where R.Bound: DivisiveArithmetic {
        let second: R.Bound = 1_000_000_000
        let time = DispatchTime.now().uptimeNanoseconds
        try await task()
        guard
            let span = R.Bound(
                exactly: DispatchTime.now().uptimeNanoseconds - time
            ),
            case let duration = span / second
        else { XCTFail("Invalid range type: \(R.self)"); return }
        let assertions = {
            XCTAssertTrue(
                range.contains(duration),
                "\(duration) not present in \(range)"
            )
        }
        runAssertions(with: name, assertions)
    }

    static func sleep<T: BinaryInteger>(seconds: T) async throws {
        let second: T = 1_000_000_000
        try await Task.sleep(nanoseconds: UInt64(exactly: seconds * second)!)
    }

    static func sleep<T: BinaryFloatingPoint>(seconds: T) async throws {
        let second: T = 1_000_000_000
        try await Task.sleep(nanoseconds: UInt64(exactly: seconds * second)!)
    }
}

extension AsyncObject {
    @Sendable
    @inlinable
    func wait(forSeconds seconds: UInt64) async throws {
        return try await self.wait(forNanoseconds: seconds * 1_000_000_000)
    }
}

protocol DivisiveArithmetic: Numeric {
    static func / (lhs: Self, rhs: Self) -> Self
    static func /= (lhs: inout Self, rhs: Self)
}

extension Int: DivisiveArithmetic {}
extension Double: DivisiveArithmetic {}
extension UInt64: DivisiveArithmetic {}
