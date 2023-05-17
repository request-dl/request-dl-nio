/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class AsyncQueue: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()
        private let priority: _Concurrency.TaskPriority

        // MARK: - Unsafe properties

        private var _operations: [() async -> Void]
        private var _isRunning = false

        // MARK: - Inits

        init(priority: _Concurrency.TaskPriority = .utility) {
            self.priority = priority
            self._operations = []
        }

        // MARK: - Internal properties

        func addOperation(_ operation: @escaping () async -> Void) {
            lock.withLock {
                _operations.insert(operation, at: .zero)
                _runIfNeeded()
            }
        }

        // MARK: - Private methods

        private func _runIfNeeded() {
            guard !_isRunning else {
                return
            }

            _isRunning = true
            _runFirstOperation(true)
        }

        private func _runFirstOperation(_ isStateLock: Bool) {
            isStateLock ? () : lock.lock()
            defer { isStateLock ? () : lock.unlock() }

            guard let operation = _operations.popLast() else {
                _isRunning = false
                return
            }

            _Concurrency.Task(priority: priority) {
                await operation()
                _runFirstOperation(false)
            }
        }
    }
}
