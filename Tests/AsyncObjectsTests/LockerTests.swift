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

    func testLockReleasedAfterError() throws {
        let lock = Locker()
        XCTAssertFalse(lock.isNested)
        XCTAssertThrowsError(
            try lock.perform {
                defer { XCTAssertTrue(lock.isNested) }
                XCTAssertTrue(lock.isNested)
                throw CancellationError()
            }
        )
        XCTAssertFalse(lock.isNested)
    }

    func testNestedLocking() {
        let lock = Locker()
        XCTAssertFalse(lock.isNested)
        let _: UInt64 = lock.perform {
            defer { XCTAssertTrue(lock.isNested) }
            XCTAssertTrue(lock.isNested)
            var generator = SystemRandomNumberGenerator()
            return lock.perform {
                defer { XCTAssertTrue(lock.isNested) }
                XCTAssertTrue(lock.isNested)
                return generator.next()
            }
        }
        XCTAssertFalse(lock.isNested)
    }

    func testLockReleasedAfterNestedError() throws {
        let lock = Locker()
        XCTAssertFalse(lock.isNested)
        XCTAssertThrowsError(
            try lock.perform {
                defer { XCTAssertTrue(lock.isNested) }
                XCTAssertTrue(lock.isNested)
                return try lock.perform {
                    defer { XCTAssertTrue(lock.isNested) }
                    XCTAssertTrue(lock.isNested)
                    throw CancellationError()
                }
            } as UInt64
        )
        XCTAssertFalse(lock.isNested)
    }
}

fileprivate extension Locker {

    var isNested: Bool {
        let threadDictionary = Thread.current.threadDictionary
        return threadDictionary[self] as? Bool ?? false
    }
}
