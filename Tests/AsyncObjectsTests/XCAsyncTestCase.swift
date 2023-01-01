import XCTest
import Dispatch
@testable import AsyncObjects

func waitUntil<T>(
    _ actor: T,
    timeout: TimeInterval,
    satisfies condition: @escaping (isolated T) async throws -> Bool
) async throws {
    let maxWait = timeout * 1E9
    try await waitForTaskCompletion(withTimeoutInNanoseconds: UInt64(maxWait)) {
        var interval = maxWait
        var retryWait = 2.0
        while case let result = try await Task(
            priority: .background,
            operation: { try await condition(actor) }
        ).value {
            guard !result else { break }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(retryWait))
            interval -= retryWait
            if interval < 0 {
                throw DurationTimeoutError(
                    for: UInt64(maxWait),
                    tolerance: UInt64(interval * -1)
                )
            } else if interval < retryWait / 2 {
                retryWait = max(1E9, retryWait.squareRoot())
            } else {
                retryWait *= retryWait
            }
        }
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep<T: BinaryInteger>(seconds: T) async throws {
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
extension Task where Success == Never, Failure == Never {

    static func sleep<C: Clock, T: BinaryInteger>(
        seconds: T,
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

extension Optional where Wrapped: AnyObject {
    func assertReleased(
        file: StaticString = #filePath,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        switch self {
        case .none:
            break
        case .some(let value):
            let wr = _getUnownedRetainCount(value) + _getWeakRetainCount(value)
            let rc = _getRetainCount(value) - wr
            XCTAssertEqual(rc, 0, file: file, line: line)
        }
    }
}
