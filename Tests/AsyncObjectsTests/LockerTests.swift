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
        DispatchQueue.concurrentPerform(iterations: 5) { count in
            lock.perform {
                iterations += 1
            }
        }
        XCTAssertEqual(iterations, 5)
    }
}
