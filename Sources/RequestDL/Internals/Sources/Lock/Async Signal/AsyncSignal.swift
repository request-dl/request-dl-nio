import Foundation

public final class AsyncSignal: Sendable {

    private final class Storage: @unchecked Sendable {

        let lock = Lock()

        var _isLocked = false
        var _pendingOperations = [AsyncOperation]()

        init(isLocked: Bool) {
            _isLocked = isLocked
        }

        deinit {
            while let operation = _pendingOperations.popLast() {
                operation.resume()
            }
        }
    }

    // MARK: - Unsafe properties

    private let storage: Storage

    // MARK: - Inits

    public init(_ signal: Bool = false) {
        storage = .init(isLocked: !signal)
    }

    // MARK: - Public properties

    public func signal() {
        storage.lock.withLock {
            storage._isLocked = false

            while let operation = storage._pendingOperations.popLast() {
                operation.resume()
            }
        }
    }

    public func lock() {
        storage.lock.withLock {
            storage._isLocked = true
        }
    }

    public func wait() async {
        let operation = AsyncOperation()

        let lock = storage.lock
        weak var storage = storage

        await withTaskCancellationHandler {
            await withUnsafeContinuation {
                operation.schedule($0)

                lock.withLock {
                    guard storage?._isLocked ?? false else {
                        operation.resume()
                        return
                    }

                    guard storage?._pendingOperations.insert(operation, at: .zero) == nil else {
                        return
                    }

                    operation.resume()
                }
            }
        } onCancel: {
            lock.withLock {
                operation.cancelled()
            }
        }
    }
}
