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
            XCTContext.runActivity(named: name) { _ in
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
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line,
        for task: () async throws -> Void
    ) async rethrows where T: Comparable {
        let second: T = 1_000_000_000
        let time = DispatchTime.now().uptimeNanoseconds
        try await task()
        guard
            let span = T(exactly: DispatchTime.now().uptimeNanoseconds - time),
            case let duration = span / second
        else {
            XCTFail("Invalid number type: \(T.self)", file: file, line: line)
            return
        }

        let assertions = {
            XCTAssertLessThanOrEqual(
                duration, seconds + 3,
                file: file, line: line
            )
            XCTAssertGreaterThanOrEqual(
                duration, seconds - 3,
                file: file, line: line
            )
        }
        runAssertions(with: name, assertions)
    }

    static func checkExecInterval<R: RangeExpression>(
        name: String? = nil,
        durationInRange range: R,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line,
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
        else {
            XCTFail("Invalid range type: \(R.self)", file: file, line: line)
            return
        }

        let assertions = {
            XCTAssertTrue(
                range.contains(duration),
                "\(duration) not present in \(range)",
                file: file, line: line
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

#if swift(>=5.7)
@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
@MainActor
extension XCTestCase {

    static func checkExecInterval<C: Clock>(
        name: String? = nil,
        duration: C.Instant.Duration = .zero,
        clock: C,
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line,
        for task: () async throws -> Void
    ) async rethrows where C.Duration == Duration {
        let result = try await clock.measure { try await task() }
        let assertions = {
            XCTAssertLessThanOrEqual(
                abs(duration.components.seconds - result.components.seconds), 3,
                file: file, line: line
            )
        }
        runAssertions(with: name, assertions)
    }

    static func sleep<C: Clock, T: BinaryInteger>(
        seconds: T,
        clock: C
    ) async throws where C.Duration == Duration {
        try await Task.sleep(
            until: clock.now.advanced(by: .seconds(seconds)),
            clock: clock
        )
    }

    static func sleep<C: Clock>(
        seconds: Double,
        clock: C
    ) async throws where C.Duration == Duration {
        try await Task.sleep(
            until: clock.now.advanced(by: .seconds(seconds)),
            clock: clock
        )
    }
}

@available(macOS 13, iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *)
extension AsyncObject {
    @Sendable
    @inlinable
    func wait<T: BinaryInteger, C: Clock>(
        forSeconds seconds: T,
        clock: C
    ) async throws where C.Duration == Duration {
        return try await self.wait(
            until: clock.now.advanced(by: .seconds(seconds)),
            tolerance: .microseconds(1),
            clock: clock
        )
    }
}
#endif

protocol DivisiveArithmetic: Numeric {
    static func / (lhs: Self, rhs: Self) -> Self
    static func /= (lhs: inout Self, rhs: Self)
}

extension Int: DivisiveArithmetic {}
extension Double: DivisiveArithmetic {}
extension UInt64: DivisiveArithmetic {}
