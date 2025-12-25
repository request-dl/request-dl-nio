import Foundation

public final class AsyncLock: Sendable {

    private final class Storage: @unchecked Sendable {

        var isLocked = false
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
        lock.withLock {
            guard _storage.isLocked else {
                return
            }

            var scheduledOperation: AsyncOperation?

            while let operation = _storage.pendingOperations.popLast() {
                if !operation.isScheduled {
                    continue
                }

                scheduledOperation = operation
                break
            }

            _storage.isLocked = !_storage.pendingOperations.isEmpty

            scheduledOperation?.resume()
        }
    }

    public func lock() async {
        let operation = AsyncOperation()

        let lock = lock
        weak var storage = _storage

        await withTaskCancellationHandler {
            await withUnsafeContinuation {
                operation.schedule($0)

                lock.withLock {
                    guard let storage else {
                        operation.resume()
                        return
                    }

                    guard storage.isLocked else {
                        storage.isLocked = true
                        operation.resume()
                        return
                    }

                    storage.pendingOperations.insert(operation, at: .zero)
                }
            }
        } onCancel: {
            lock.withLock {
                operation.cancelled()
            }
        }
    }
}
