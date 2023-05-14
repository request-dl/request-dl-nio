/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct AsyncStream<Element: Sendable>: Sendable, Hashable, AsyncSequence {

        struct AsyncIterator: AsyncIteratorProtocol {

            // MARK: - Private properties

            fileprivate var node: () async -> Node?

            // MARK: - Internal methods

            mutating func next() async throws -> Element? {
                guard let node = await node() else {
                    return nil
                }

                self.node = { await node.next() }

                switch node.value {
                case .success(let value):
                    return value
                case .failure(let error):
                    throw error
                }
            }
        }

        private final class Storage: @unchecked Sendable {

            // MARK: - Private properties

            private let lock = AsyncLock()
            private let rootSignal = AsyncSignal()

            // MARK: - Unsafe properties

            private var _root: Node?
            private weak var _last: Node?

            private var _isClosed = false

            // MARK: - Inits
            init() {}

            func append(_ value: Result<Element, Error>) async {
                await lock.withLock {
                    guard !_isClosed else {
                        return
                    }

                    let next = Node(value)

                    if let node = _last ?? _root {
                        await node.append(next)
                        _last = next
                    } else {
                        _root = next
                        _last = next
                        rootSignal.signal()
                    }

                    if case .failure = value {
                        await _close()
                    }
                }
            }

            func close() async {
                await lock.withLock {
                    await _close()
                }
            }

            func root() async -> Node? {
                await rootSignal.wait()

                return await lock.withLock {
                    _root
                }
            }

            // MARK: - Unsafe methods

            private func _close() async {
                guard !_isClosed else {
                    return
                }

                _isClosed = true
                await (_last ?? _root)?.close()

                if _root == nil {
                    rootSignal.signal()
                }
            }
        }

        fileprivate final class Node: @unchecked Sendable {

            // MARK: - Internal properties

            let value: Result<Element, Error>

            // MARK: - Private properties

            private let lock = AsyncLock()
            private let nextSignal = AsyncSignal()

            // MARK: - Unsafe properties

            private var _next: Node?
            private var _isClosed: Bool = false

            // MARK: - Inits

            init(_ value: Result<Element, Error>) {
                self.value = value
                self._next = nil
            }

            // MARK: - Internal methods

            func next() async -> Node? {
                await nextSignal.wait()

                return await lock.withLock {
                    _next
                }
            }

            func append(_ node: Node) async {
                await lock.withLock {
                    guard _next == nil else {
                        fatalError()
                    }

                    _next = node
                    _isClosed = true
                    nextSignal.signal()
                }
            }

            func close() async {
                await lock.withLock {
                    guard !_isClosed else {
                        return
                    }

                    _isClosed = true
                    nextSignal.signal()
                }
            }
        }

        private final class Queue: @unchecked Sendable {

            private let lock = Lock()
            private let priority: _Concurrency.TaskPriority

            private var _operations: [() async -> Void]
            private var _isRunning = false

            init(priority: _Concurrency.TaskPriority = .utility) {
                self.priority = priority
                self._operations = []
            }

            func addOperation(_ operation: @escaping () async -> Void) {
                lock.withLock {
                    _operations.append(operation)
                    _runIfNeeded()
                }
            }

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

                guard let operation = _operations.first else {
                    _isRunning = false
                    return
                }

                _operations.removeFirst()

                _Concurrency.Task(priority: priority) {
                    await operation()
                    _runFirstOperation(false)
                }
            }
        }

        // MARK: - Private properties

        private let storage = Storage()
        private let queue = Queue()

        // MARK: - Inits

        init() {}

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.storage === rhs.storage
        }

        static func empty() -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.close()
            return asyncStream
        }

        static func constant(_ value: Element) -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.append(.success(value))
            asyncStream.close()
            return asyncStream
        }

        // MARK: - Internal methods

        func append(_ value: Result<Element, Error>) {
            queue.addOperation {
                await storage.append(value)
            }
        }

        func close() {
            queue.addOperation {
                await storage.close()
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            .init(node: { await storage.root() })
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(storage))
        }
    }
}
