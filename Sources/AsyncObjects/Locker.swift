#if canImport(Darwin)
@_implementationOnly import Darwin
#elseif canImport(Glibc)
@_implementationOnly import Glibc
#elseif canImport(WinSDK)
@_implementationOnly import WinSDK
#endif

/// A synchronization object that can be used to provide exclusive access to threads.
///
/// The values stored in the lock should be considered opaque and implementation defined,
/// they contain thread ownership information that the system may use to attempt to resolve priority inversions.
/// This lock must be unlocked from the same thread that locked it,
/// attempts to unlock from a different thread will cause an assertion aborting the process.
/// This lock must not be accessed from multiple processes or threads via shared or multiply-mapped memory,
/// the lock implementation relies on the address of the lock value and owning process.
public final class Locker: Equatable, Hashable, Sendable {
    #if canImport(Darwin)
    /// A type representing data for an unfair lock.
    typealias Primitive = os_unfair_lock
    #elseif canImport(Glibc)
    /// A type representing a MUTual EXclusion object.
    typealias Primitive = pthread_mutex_t
    #elseif canImport(WinSDK)
    /// A type representing a slim reader/writer (SRW) lock.
    typealias Primitive = SRWLOCK
    #endif

    /// Pointer type pointing to platform dependent lock primitive.
    typealias PlatformLock = UnsafeMutablePointer<Primitive>
    /// Pointer to platform dependent lock primitive.
    let platformLock: PlatformLock

    /// Creates lock object with the provided pointer to platform dependent lock primitive.
    ///
    /// - Parameter platformLock: Pointer to platform dependent lock primitive.
    /// - Returns: The newly created lock object.
    init(withLock platformLock: PlatformLock) {
        self.platformLock = platformLock
    }

    /// Allocates and initializes platform dependent lock primitive.
    ///
    /// - Returns: The newly created lock object.
    public init() {
        let platformLock = PlatformLock.allocate(capacity: 1)
        #if canImport(Darwin)
        platformLock.initialize(to: os_unfair_lock())
        #elseif canImport(Glibc)
        pthread_mutex_init(platformLock, nil)
        #elseif canImport(WinSDK)
        InitializeSRWLock(platformLock)
        #endif
        self.platformLock = platformLock
    }

    deinit {
        #if canImport(Glibc)
        pthread_mutex_destroy(platformLock)
        #endif
        platformLock.deinitialize(count: 1)
    }

    /// Acquires exclusive lock.
    ///
    /// If a thread has already acquired lock and hasn't released lock yet,
    /// other threads will wait for lock to be released and then acquire lock
    /// in order of their request.
    public func lock() {
        #if canImport(Darwin)
        os_unfair_lock_lock(platformLock)
        #elseif canImport(Glibc)
        pthread_mutex_lock(platformLock)
        #elseif canImport(WinSDK)
        AcquireSRWLockExclusive(platformLock)
        #endif
    }

    /// Releases exclusive lock.
    ///
    /// A lock must be unlocked only from the same thread in which it was locked.
    /// Attempting to unlock from a different thread causes a runtime error.
    public func unlock() {
        #if canImport(Darwin)
        os_unfair_lock_unlock(platformLock)
        #elseif canImport(Glibc)
        pthread_mutex_unlock(platformLock)
        #elseif canImport(WinSDK)
        ReleaseSRWLockExclusive(platformLock)
        #endif
    }

    /// Performs a critical piece of work synchronously after acquiring the lock
    /// and releases lock when task completes.
    ///
    /// Use this to perform critical tasks or provide access to critical resource
    /// that require exclusivity among other concurrent tasks.
    ///
    /// - Parameter critical: The critical task to perform.
    /// - Returns: The result from the critical task.
    /// - Throws: Error occurred running critical task.
    @discardableResult
    public func perform<R>(_ critical: () throws -> R) rethrows -> R {
        lock()
        defer { unlock() }
        return try critical()
    }

    /// Returns a Boolean value indicating whether two locks are equal.
    ///
    /// Checks if two lock objects point to the same platform dependent lock primitive.
    ///
    /// - Parameters:
    ///   - lhs: A lock to compare.
    ///   - rhs: Another lock to compare.
    ///
    /// - Returns: If the lock objects compared are equal.
    public static func == (lhs: Locker, rhs: Locker) -> Bool {
        return lhs.platformLock == rhs.platformLock
    }

    /// Hashes the pointer to platform dependent lock primitive
    /// by feeding into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use when combining
    ///                     the components of this instance.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(platformLock)
    }
}
