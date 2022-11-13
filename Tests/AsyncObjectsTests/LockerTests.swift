import XCTest
@testable import AsyncObjects

class LockerTests: XCTestCase {

    func testEquatableImplementation() {
        let lock1 = Locker()
        let lock2 = Locker(withLock: lock1.platformLock)
        XCTAssertEqual(lock1, lock2)
    }

    func testHashableImplementation() {
        let lock1 = Locker()
        let lock2 = Locker(withLock: lock1.platformLock)
        let table = [lock1: 1]
        XCTAssertEqual(table[lock2], 1)
    }

    func testSynchronization() {
        let lock = Locker()
        var iterations = 0
        DispatchQueue.concurrentPerform(iterations: 5) { _ in
            lock.perform {
                iterations += 1
            }
        }
        XCTAssertEqual(iterations, 5)
    }

    static func threadLocalValue<T>(forKey key: NSCopying) -> T? {
        let threadDictionary = Thread.current.threadDictionary
        return threadDictionary[key] as? T
    }

    func testLockReleasedAfterError() throws {
        let lock = Locker()
        XCTAssertFalse(Self.threadLocalValue(forKey: lock) ?? false)
        XCTAssertThrowsError(
            try lock.perform {
                defer {
                    XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                }
                XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                throw CancellationError()
            }
        )
        XCTAssertFalse(Self.threadLocalValue(forKey: lock) ?? false)
    }

    func testNestedLocking() {
        let lock = Locker()
        XCTAssertFalse(Self.threadLocalValue(forKey: lock) ?? false)
        let _: UInt64 = lock.perform {
            defer {
                XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
            }
            XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
            var generator = SystemRandomNumberGenerator()
            return lock.perform {
                defer {
                    XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                }
                XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                return generator.next()
            }
        }
        XCTAssertFalse(Self.threadLocalValue(forKey: lock) ?? false)
    }

    func testLockReleasedAfterNestedError() throws {
        let lock = Locker()
        XCTAssertFalse(Self.threadLocalValue(forKey: lock) ?? false)
        XCTAssertThrowsError(
            try lock.perform {
                defer {
                    XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                }
                XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                return try lock.perform {
                    defer {
                        XCTAssertTrue(
                            Self.threadLocalValue(forKey: lock) ?? false
                        )
                    }
                    XCTAssertTrue(Self.threadLocalValue(forKey: lock) ?? false)
                    throw CancellationError()
                }
            } as UInt64
        )
        XCTAssertFalse(Self.threadLocalValue(forKey: lock) ?? false)
    }
}
