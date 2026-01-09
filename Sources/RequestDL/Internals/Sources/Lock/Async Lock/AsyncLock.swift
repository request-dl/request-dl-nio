import Foundation

public final class AsyncLock: Sendable {

    private final class Storage: @unchecked Sendable {

        var runningOperation: AsyncOperation?
        var pendingOperations = [AsyncOperation]()

        deinit {
            while let operation = pendingOperations.popLast() {
                operation.resume()
            }
        }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private let _storage = Storage()

    // MARK: - Inits

    public init() {}

    // MARK: - Public properties

    public func withLock<Value: Sendable>(isolation: isolated (any Actor)? = #isolation, _ block: @Sendable () async throws -> Value) async rethrows -> Value {
        await lock()
        defer { unlock() }

        return try await block()
    }

    public func withLockVoid(isolation: isolated (any Actor)? = #isolation, _ block: @Sendable () async throws -> Void) async rethrows {
        await lock()
        defer { unlock() }

        try await block()
    }

    public func unlock() {
        let runningOperation = lock.withLock { () -> AsyncOperation? in
            guard
                let  runningOperation = _storage.runningOperation,
                [.cancelled, .finished].contains(runningOperation.state)
            else { return nil }

            var pendingOperation: AsyncOperation?

            while let operation = _storage.pendingOperations.popLast() {
                if operation.state != .waiting {
                    continue
                }

                pendingOperation = operation
                break
            }

            _storage.runningOperation = pendingOperation
            return pendingOperation
        }

        runningOperation?.resume()
    }

    public func lock() async {
        let operation = AsyncOperation()

        let lock = lock
        #if swift(>=6.2)
        weak let storage = _storage
        #else
        weak var storage = _storage
        #endif

        await withTaskCancellationHandler {
            await withUnsafeContinuation {
                operation.schedule($0)

                let runningOperation = lock.withLock { () -> AsyncOperation? in
                    guard let storage else {
                        return operation
                    }

                    guard storage.runningOperation != nil else {
                        storage.runningOperation = operation
                        return operation
                    }

                    storage.pendingOperations.insert(operation, at: .zero)
                    return nil
                }

                runningOperation?.resume()
            }
        } onCancel: { [weak self] in
            #if swift(<6.2)
            let storage = self?._storage
            #endif

            Task.detached {
                guard let self else {
                    return
                }

                operation.cancelled()

                let didCancelRunningOperation = lock.withLock {
                    #if swift(>=6.2)
                    guard let storage else {
                        return false
                    }
                    #endif

                    return operation === storage.runningOperation
                }

                guard didCancelRunningOperation else {
                    return
                }

                self.unlock()
            }
        }
    }
}
