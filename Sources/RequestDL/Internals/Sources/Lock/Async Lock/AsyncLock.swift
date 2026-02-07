import Foundation

/// A synchronization primitive that provides mutual exclusion for asynchronous operations.
/// It allows only one task to access a critical section at a time.
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

    /// Creates a new AsyncLock instance.
    public init() {}

    // MARK: - Public properties

    /// Executes the provided closure while maintaining the lock.
    /// - Parameter block: The closure to execute while holding the lock.
    /// - Returns: The result of the closure.
    public func withLock<Value: Sendable>(isolation: isolated (any Actor)? = #isolation, _ block: @Sendable () async throws -> Value) async rethrows -> Value {
        await lock(isolation: isolation)
        defer { unlock() }

        return try await block()
    }

    /// Executes the provided closure while maintaining the lock, without returning a value.
    /// - Parameter block: The closure to execute while holding the lock.
    public func withLockVoid(isolation: isolated (any Actor)? = #isolation, _ block: @Sendable () async throws -> Void) async rethrows {
        await lock(isolation: isolation)
        defer { unlock() }

        try await block()
    }

    /// Unlocks the lock and allows the next waiting operation to proceed.
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

    /// Acquires the lock. If the lock is already held by another task, this method will suspend
    /// until the lock becomes available.
    public func lock(isolation: isolated (any Actor)? = #isolation) async {
        let operation = AsyncOperation()

        let lock = lock
        #if swift(>=6.2.3)
        weak let storage = _storage
        #else
        weak var storage = _storage
        #endif

        await withTaskCancellationHandler(
            operation: {
                await withUnsafeContinuation(isolation: isolation) {
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
            },
            onCancel: { [weak self] in
                #if swift(<6.2.3)
                let storage = self?._storage
                #endif

                Task.detached {
                    guard let self else {
                        return
                    }

                    let didCancelRunningOperation = lock.withLock {
                        operation.cancelled()

                        guard let storage else {
                            return false
                        }

                        return operation === storage.runningOperation
                    }

                    guard didCancelRunningOperation else {
                        return
                    }

                    self.unlock()
                }
            },
            isolation: isolation
        )
    }
}
