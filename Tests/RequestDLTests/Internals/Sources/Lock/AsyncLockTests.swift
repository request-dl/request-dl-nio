import Testing
@testable import RequestDL

struct AsyncLockTests {

    @Test
    func basicLock() async throws {
        let asyncLock = AsyncLock()

        let counter = InlineProperty(wrappedValue: 0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await asyncLock.withLock {
                        let current = counter.wrappedValue
                        try? await Task.sleep(nanoseconds: 1000)
                        counter.wrappedValue = current + 1
                    }
                }
            }
        }

        #expect(counter.wrappedValue == 100)
    }

    @Test
    func lockWithReturnValue() async throws {
        let asyncLock = AsyncLock()
        let value = InlineProperty(wrappedValue: 0)

        let result = await asyncLock.withLock {
            value.wrappedValue = 42
            return value.wrappedValue * 2
        }

        #expect(result == 84)
        #expect(value.wrappedValue == 42)
    }

    @Test
    func voidLock() async throws {
        let asyncLock = AsyncLock()
        let called = InlineProperty(wrappedValue: false)

        await asyncLock.withLockVoid {
            called.wrappedValue = true
            try? await Task.sleep(nanoseconds: 1000)
        }

        #expect(called.wrappedValue == true)
    }

    @Test
    func exclusiveAccess() async throws {
        let asyncLock = AsyncLock()
        let sharedResource = InlineProperty(wrappedValue: 0)
        let accessOrder = InlineProperty(wrappedValue: [Int]())

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await asyncLock.withLock {
                        let taskId = i
                        sharedResource.wrappedValue = taskId
                        try? await Task.sleep(nanoseconds: 100_000) // 100ms
                        #expect(sharedResource.wrappedValue == taskId)
                        accessOrder.wrappedValue.append(taskId)
                    }
                }
            }
        }

        #expect(accessOrder.wrappedValue.count == 10)
    }

    @Test
    func lockReentrancy() async throws {
        let asyncLock = AsyncLock()
        let counter = InlineProperty(wrappedValue: 0)

        await #expect(throws: CancellationError.self) {
            try await asyncLock.withLock {
                counter.wrappedValue += 1

                try await withTaskTimeout(seconds: 1) {
                    try await asyncLock.withLock {
                        try Task.checkCancellation()
                        counter.wrappedValue += 1
                    }
                }

                counter.wrappedValue += 1
            }
        }

        #expect(counter.wrappedValue == 1)
    }

    @Test
    func concurrentPerformance() async throws {
        let asyncLock = AsyncLock()
        let lock = Lock()
        let iterations = 1000
        let counter = InlineProperty(wrappedValue: 0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< iterations {
                group.addTask {
                    await asyncLock.withLock {
                        lock.withLock {
                            counter.wrappedValue += 1
                        }
                    }
                }
            }
        }

        #expect(counter.wrappedValue == iterations)
    }

    @Test
    func errorHandling() async throws {
        let asyncLock = AsyncLock()

        struct TestError: Error {}

        await #expect(throws: TestError.self) {
            try await asyncLock.withLock {
                throw TestError()
            }
        }

        let executed = InlineProperty(wrappedValue: false)
        await asyncLock.withLock {
            executed.wrappedValue = true
        }

        #expect(executed.wrappedValue == true)
    }

    @Test
    func manualLockUnlock() async throws {
        let asyncLock = AsyncLock()
        let counter = InlineProperty(wrappedValue: 0)

        await asyncLock.lock()
        counter.wrappedValue += 1
        asyncLock.unlock()

        await asyncLock.lock()
        counter.wrappedValue += 1
        asyncLock.unlock()

        #expect(counter.wrappedValue == 2)
    }

    @Test
    func cancellingTask() async throws {
        let lock = AsyncLock()

        let task0 = Task {
            await lock.lock()
        }

        let task1 = Task {
            await lock.lock()
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)

        await task0.value
        task1.cancel()
        lock.unlock()

        try await withTaskTimeout(seconds: 1) {
            await lock.lock()
        }

        lock.unlock()
    }

    @Test
    func cancellingAllTasksButKeepingTheLastOne() async throws {
        let lock = AsyncLock()
        let lastOperationSignal = AsyncSignal()
        let isListeningTheSignal = InlineProperty(wrappedValue: false)

        let tasks = (0 ..< 100).map { index in
            Task {
                await lock.lock()

                guard index > .zero else {
                    return
                }

                if index < 99 || !isListeningTheSignal.wrappedValue {
                    Issue.record("Not expected to be called")
                    return
                }

                lastOperationSignal.signal()
                lock.unlock()
            }
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)

        tasks[1 ..< 99].forEach { $0.cancel() }

        try await Task.sleep(nanoseconds: 1_000_000_000)
        tasks[0].cancel()

        try await Task.sleep(nanoseconds: 1_000_000_000)
        isListeningTheSignal.wrappedValue = true
        lock.unlock()

        try await withTaskTimeout(seconds: 1) {
            await lastOperationSignal.wait()
            await lock.lock()
        }

        lock.unlock()
    }
}
