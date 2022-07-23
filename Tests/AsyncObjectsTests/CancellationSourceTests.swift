import XCTest
@testable import AsyncObjects

class CancellationSourceTests: XCTestCase {

    func testTaskCancellation() async throws {
        let source = await CancellationSource()
        let task = Task {
            try await Task.sleep(nanoseconds: UInt64(10E9))
        }
        await source.register(task: task)
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithTimeout() async throws {
        let source = CancellationSource(cancelAfterNanoseconds: UInt64(5E9))
        let task = Task {
            try await Task.sleep(nanoseconds: UInt64(10E9))
        }
        await source.register(task: task)
        try await Task.sleep(nanoseconds: UInt64(6E9))
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithLinkedSource() async throws {
        let parentSource = await CancellationSource()
        let source = await CancellationSource(linkedWith: parentSource)
        let task = Task {
            try await Task.sleep(nanoseconds: UInt64(10E9))
        }
        await source.register(task: task)
        await parentSource.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithMultipleLinkedSources() async throws {
        let parentSource1 = await CancellationSource()
        let parentSource2 = await CancellationSource()
        let source = await CancellationSource(
            linkedWith: parentSource1, parentSource2
        )
        let task = Task {
            try await Task.sleep(nanoseconds: UInt64(10E9))
        }
        await source.register(task: task)
        await parentSource1.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithSourcePassedOnInitialization() async throws {
        let source = await CancellationSource()
        let task = await Task(cancellationSource: source) {
            do {
                try await Task.sleep(nanoseconds: UInt64(10E9))
                XCTFail()
            } catch {}
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testDetachedTaskCancellationWithSourcePassedOnInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = await Task.detached(cancellationSource: source) {
            do {
                try await Task.sleep(nanoseconds: UInt64(10E9))
                XCTFail()
            } catch {}
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingTaskCancellationWithSourcePassedOnInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = try await Task(cancellationSource: source) {
            try await Task.sleep(nanoseconds: UInt64(10E9))
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingDetachedTaskCancellationWithSourcePassedOnInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = try await Task.detached(cancellationSource: source) {
            try await Task.sleep(nanoseconds: UInt64(10E9))
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func createTaskWithCancellationSource(
        _ source: CancellationSource
    ) -> Task<Void, Never> {
        return Task(cancellationSource: source) {
            do {
                try await Task.sleep(nanoseconds: UInt64(10E9))
                XCTAssertTrue(Task.isCancelled)
            } catch {}
        }
    }

    func testTaskCancellationWithSourcePassedOnSyncInitialization() async throws
    {
        let source = await CancellationSource()
        let task = createTaskWithCancellationSource(source)
        Task {
            try await Task.sleep(nanoseconds: UInt64(2E9))
            await source.cancel()
        }
        await task.value
    }

    func createDetachedTaskWithCancellationSource(
        _ source: CancellationSource
    ) -> Task<Void, Never> {
        return Task.detached(cancellationSource: source) {
            do {
                try await Task.sleep(nanoseconds: UInt64(10E9))
                XCTFail()
            } catch {}
        }
    }

    func testDetachedTaskCancellationWithSourcePassedOnSyncInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = createDetachedTaskWithCancellationSource(source)
        Task {
            try await Task.sleep(nanoseconds: UInt64(2E9))
            await source.cancel()
        }
        await task.value
    }

    func createThrowingTaskWithCancellationSource(
        _ source: CancellationSource
    ) throws -> Task<Void, Error> {
        return try Task(cancellationSource: source) {
            try await Task.sleep(nanoseconds: UInt64(10E9))
            XCTFail()
        }
    }

    func testThrowingTaskCancellationWithSourcePassedOnSyncInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = try createThrowingTaskWithCancellationSource(source)
        Task {
            try await Task.sleep(nanoseconds: UInt64(2E9))
            await source.cancel()
        }
        let value: Void? = try? await task.value
        XCTAssertNil(value)
    }

    func createThrowingDetachedTaskWithCancellationSource(
        _ source: CancellationSource
    ) throws -> Task<Void, Error> {
        return try Task.detached(cancellationSource: source) {
            try await Task.sleep(nanoseconds: UInt64(10E9))
            XCTFail()
        }
    }

    func
        testThrowingDetachedTaskCancellationWithSourcePassedOnSyncInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = try createThrowingDetachedTaskWithCancellationSource(source)
        Task {
            try await Task.sleep(nanoseconds: UInt64(2E9))
            await source.cancel()
        }
        let value: Void? = try? await task.value
        XCTAssertNil(value)
    }
}
