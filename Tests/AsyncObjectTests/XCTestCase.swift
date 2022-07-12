import XCTest

extension XCTestCase {
    func checkExecInterval(
        for task: () async throws -> Void,
        durationInSeconds seconds: Int = 0
    ) async rethrows {
        let time = DispatchTime.now()
        try await task()
        let execTime = time.distance(to: DispatchTime.now())
        switch execTime {
        case .seconds(let value):
            XCTAssertEqual(seconds, value)
        case .microseconds(let value):
            XCTAssertEqual(seconds, value/Int(1E6))
        case .milliseconds(let value):
            XCTAssertEqual(seconds, value/Int(1E3))
        case .nanoseconds(let value):
            XCTAssertEqual(seconds, value/Int(1E9))
        case .never: fallthrough
        @unknown default:
            NSException(
                name: NSExceptionName(rawValue: "UnExpectedInterval"),
                reason: "UnExpected time interval"
            ).raise()
        }
    }
}
