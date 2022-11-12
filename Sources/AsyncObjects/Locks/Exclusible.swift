/// A type that provides exclusive access to threads.
///
/// The `perform(_:)` method executes a synchronous
/// piece of work exclusively for a single instance of this type.
@rethrows
@usableFromInline
internal protocol Exclusible {
    /// Initializes a MUTual EXclusion object.
    ///
    /// - Returns: The newly created MUTual EXclusion object.
    init()
    /// Performs a critical piece of work synchronously after acquiring the MUTual
    /// EXclusion object and releases MUTual EXclusion object when task completes.
    ///
    /// Use this to perform critical tasks or provide access to critical resource
    /// that require exclusivity among other concurrent tasks.
    ///
    /// - Parameter critical: The critical task to perform.
    /// - Returns: The result from the critical task.
    /// - Throws: Error occurred running critical task.
    @discardableResult
    func perform<R>(_ critical: () throws -> R) rethrows -> R
}
