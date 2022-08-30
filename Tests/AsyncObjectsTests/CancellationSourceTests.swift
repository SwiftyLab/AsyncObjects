import XCTest
@testable import AsyncObjects

@MainActor
class CancellationSourceTests: XCTestCase {

    func testTaskCancellation() async throws {
        let source = await CancellationSource()
        let task = Task {
            try await Self.sleep(seconds: 1)
        }
        await source.register(task: task)
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithTimeout() async throws {
        let source = CancellationSource(cancelAfterNanoseconds: UInt64(1E9))
        let task = Task {
            try await Self.sleep(seconds: 2)
        }
        await source.register(task: task)
        try await Self.sleep(seconds: 2)
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithLinkedSource() async throws {
        let parentSource = await CancellationSource()
        let source = await CancellationSource(linkedWith: parentSource)
        let task = Task {
            try await Self.sleep(seconds: 1)
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
            try await Self.sleep(seconds: 1)
        }
        await source.register(task: task)
        await parentSource1.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testTaskCancellationWithSourcePassedOnInitialization() async throws {
        let source = await CancellationSource()
        let task = await Task(cancellationSource: source) {
            do {
                try await Self.sleep(seconds: 1)
                XCTFail("Unexpected task progression")
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
                try await Self.sleep(seconds: 1)
                XCTFail("Unexpected task progression")
            } catch {}
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingTaskCancellationWithSourcePassedOnInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = await Task(cancellationSource: source) {
            try await Self.sleep(seconds: 1)
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func testThrowingDetachedTaskCancellationWithSourcePassedOnInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = await Task.detached(cancellationSource: source) {
            try await Self.sleep(seconds: 1)
        }
        await source.cancel()
        XCTAssertTrue(task.isCancelled)
    }

    func createTaskWithCancellationSource(
        _ source: CancellationSource
    ) -> Task<Void, Never> {
        return Task(cancellationSource: source) {
            do {
                try await Self.sleep(seconds: 1)
            } catch {
                XCTAssertTrue(Task.isCancelled)
            }
        }
    }

    func testTaskCancellationWithSourcePassedOnSyncInitialization() async throws
    {
        let source = await CancellationSource()
        let task = createTaskWithCancellationSource(source)
        Task {
            try await Self.sleep(seconds: 2)
            await source.cancel()
        }
        await task.value
    }

    func createDetachedTaskWithCancellationSource(
        _ source: CancellationSource
    ) -> Task<Void, Never> {
        return Task.detached(cancellationSource: source) {
            do {
                try await Self.sleep(seconds: 2)
                XCTFail("Unexpected task progression")
            } catch {}
        }
    }

    func testDetachedTaskCancellationWithSourcePassedOnSyncInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = createDetachedTaskWithCancellationSource(source)
        Task {
            try await Self.sleep(seconds: 1)
            await source.cancel()
        }
        await task.value
    }

    func createThrowingTaskWithCancellationSource(
        _ source: CancellationSource
    ) -> Task<Void, Error> {
        return Task(cancellationSource: source) {
            try await Self.sleep(seconds: 2)
            XCTFail("Unexpected task progression")
        }
    }

    func testThrowingTaskCancellationWithSourcePassedOnSyncInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = createThrowingTaskWithCancellationSource(source)
        Task {
            try await Self.sleep(seconds: 1)
            await source.cancel()
        }
        let value: Void? = try? await task.value
        XCTAssertNil(value)
    }

    func createThrowingDetachedTaskWithCancellationSource(
        _ source: CancellationSource
    ) throws -> Task<Void, Error> {
        return Task.detached(cancellationSource: source) {
            try await Self.sleep(seconds: 2)
            XCTFail("Unexpected task progression")
        }
    }

    func
        testThrowingDetachedTaskCancellationWithSourcePassedOnSyncInitialization()
        async throws
    {
        let source = await CancellationSource()
        let task = try createThrowingDetachedTaskWithCancellationSource(source)
        Task {
            try await Self.sleep(seconds: 1)
            await source.cancel()
        }
        let value: Void? = try? await task.value
        XCTAssertNil(value)
    }

    func testDeinit() async throws {
        let source = await CancellationSource()
        let task = try createThrowingDetachedTaskWithCancellationSource(source)
        Task.detached {
            try await Self.sleep(seconds: 1)
            await source.cancel()
        }
        try? await task.value
        self.addTeardownBlock { [weak source] in
            XCTAssertNil(source)
        }
    }
}
