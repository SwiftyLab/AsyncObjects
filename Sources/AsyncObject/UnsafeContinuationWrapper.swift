func withUnsafeThrowingContinuationCancellationHandler<T: Sendable>(
    handler: @Sendable (UnsafeContinuation<T, Error>) -> Void,
    _ fn: (UnsafeContinuation<T, Error>) -> Void
) async throws -> T {
    typealias Continuation = UnsafeContinuation<T, Error>
    let wrapper = Continuation.Wrapper()
    let value = try await withTaskCancellationHandler {
        guard let continuation = wrapper.value else { return }
        wrapper.cancel(withError: CancellationError())
        handler(continuation)
    } operation: { () -> T in
        let value = try await withUnsafeThrowingContinuation {
            (c: Continuation) in
            wrapper.value = c
            fn(c)
        }
        return value
    }
    return value
}

extension UnsafeContinuation {
    class Wrapper {
        var value: UnsafeContinuation?

        init(value: UnsafeContinuation? = nil) {
            self.value = value
        }

        func cancel(withError error: E) {
            value?.resume(throwing: error)
        }
    }
}
