import Foundation

public final class AsyncSignal: Sendable {

    private final class Storage: @unchecked Sendable {

        var isLocked = false
        var pendingOperations = [AsyncOperation]()

        init(isLocked: Bool) {
            self.isLocked = isLocked
        }

        deinit {
            while let operation = pendingOperations.popLast() {
                operation.resume()
            }
        }
    }

    // MARK: - Private properties

    private let locker = Lock()

    // MARK: - Unsafe properties

    private let _storage: Storage

    // MARK: - Inits

    public init(_ signal: Bool = false) {
        _storage = .init(isLocked: !signal)
    }

    // MARK: - Public properties

    public func signal() {
        var operations = locker.withLock {
            _storage.isLocked = false

            let operations = _storage.pendingOperations
            _storage.pendingOperations = []
            return operations
        }

        while let operation = operations.popLast() {
            operation.resume()
        }
    }

    public func lock() {
        locker.withLock {
            _storage.isLocked = true
        }
    }

    public func wait(isolation: isolated (any Actor)? = #isolation) async {
        let operation = AsyncOperation()

        let lock = locker

        #if swift(>=6.2.3)
        weak let storage = _storage
        #else
        weak var storage = _storage
        #endif

        await withTaskCancellationHandler(
            operation: {
                await withUnsafeContinuation(isolation: isolation) {
                    operation.schedule($0)

                    let operation = lock.withLock { () -> AsyncOperation? in
                        guard let storage, storage.isLocked else {
                            return operation
                        }

                        storage.pendingOperations.insert(operation, at: .zero)
                        return nil
                    }

                    operation?.resume()
                }
            },
            onCancel: {
                Task.detached {
                    lock.withLock {
                        operation.cancelled()
                    }
                }
            },
            isolation: isolation
        )
    }
}
