/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class QueueStream<Value: Sendable>: StreamProtocol, @unchecked Sendable {

        private final class Node: @unchecked Sendable {

            // MARK: - Internal properties

            let value: Value

            var next: Node? {
                get { lock.withLock { _next } }
                set { lock.withLockVoid { _next = newValue } }
            }

            // MARK: - Private properties

            private let lock = Lock()

            // MARK: - Unsafe properties

            private var _next: Node?

            // MARK: - Inits

            init(_ value: Value) {
                self.value = value
                self._next = nil
            }
        }

        // MARK: - Internal properties

        var isOpen: Bool {
            lock.withLock { _isOpen }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _root: Node?
        private weak var _last: Node?
        private var _error: Error?
        private var _isOpen: Bool = true

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func append(_ value: Result<Value?, Error>) {
            lock.withLockVoid {
                guard _isOpen else {
                    return
                }

                switch value {
                case .failure(let failure):
                    _error = failure
                    _root = nil
                    _last = nil
                    _isOpen = false
                case .success(let value):
                    guard let value = value else {
                        _isOpen = false
                        return
                    }

                    let last = _last ?? _root
                    let node = Node(value)
                    last?.next = node
                    self._last = node
                    self._root = _root ?? node
                }
            }
        }

        func next() throws -> Value? {
            try lock.withLock {
                if let error = _error {
                    self._error = nil
                    throw error
                }

                guard let root = _root else {
                    return nil
                }

                self._root = root.next
                return root.value
            }
        }
    }
}
