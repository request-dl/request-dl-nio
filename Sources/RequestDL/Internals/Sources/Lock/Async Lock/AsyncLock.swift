/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOConcurrencyHelpers

struct AsyncLock: Sendable {

    private final class Node: @unchecked Sendable {

        // MARK: - Internal properties

        let task: Task

        var next: Node?
        weak var previous: Node?

        // MARK: - Inits

        init(_ task: Task) {
            self.task = task
            task.node = self
        }
    }

    private final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var first: Task? {
            _first?.task
        }

        var last: Task? {
            _last?.task
        }

        // MARK: - Private properties

        private var _first: Node?
        private weak var _last: Node?

        // MARK: - Internal methods

        func append(_ task: Task) {
            assert(task.node == nil)

            let node = Node(task)
            let previous = _last ?? _first

            node.previous = previous
            previous?.next = node

            _last = node
            _first = _first ?? node
        }

        func remove(_ task: Task) {
            defer { task.node = nil }

            let node = task.node.unsafelyUnwrapped

            if node === _first {
                _first = node.next
                _first?.previous = nil
                return
            }

            let previous = node.previous

            if node === last {
                _last = previous
                previous?.next = nil
                return
            }

            let next = node.next

            previous?.next = next
            next?.previous = previous
        }

        deinit {
            let isEmpty = _first == nil && _last == nil
            precondition(isEmpty, "The AsyncLock is being deallocated with pending tasks. This is not safe.")
        }
    }

    private class Task: @unchecked Sendable {

        enum State {
            case pending
            case waiting(UnsafeContinuation<Void, Never>)
            case running
            case cancelled
        }

        // MARK: - Internal properties

        var state: State
        weak var node: Node?

        // MARK: - Inits

        init(_ state: State) {
            self.state = state
        }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private let _storage: Storage

    // MARK: - inits

    init() {
        _storage = .init()
    }

    // MARK: - Internal methods

    func withLock<Value: Sendable>(
        _ body: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        await lock()
        defer { unlock() }
        return try await body()
    }

    func withLockVoid(
        _ body: @Sendable () async throws -> Void
    ) async rethrows {
        await lock()
        defer { unlock() }
        try await body()
    }

    func lock() async {
        let task = startTask()

        lock.lock()

        if _storage.first === task {
            task.state = .running
            lock.unlock()
            return
        }

        lock.unlock()
        await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                lock.withLock {
                    if case .cancelled = task.state {
                        return
                    }

                    if task === _storage.first {
                        task.state = .running
                        continuation.resume()
                        return
                    }

                    task.state = .waiting(continuation)
                }
            }
        } onCancel: {
            lock.withLock {
                if case .running = task.state {
                    return
                }

                task.state = .cancelled

                if task === _storage.first {
                    _resumeNextPendingTask()
                    return
                }

                _storage.remove(task)
            }
        }
    }

    func unlock() {
        lock.withLock {
            _resumeNextPendingTask()
        }
    }

    // MARK: - Private methods

    private func startTask() -> Task {
        lock.withLock {
            let task = Task(.pending)
            _storage.append(task)
            return task
        }
    }

    // MARK: - Unsafe methods

    private func _resumeNextPendingTask() {
        var stop = false

        while !stop, let task = _storage.first {
            switch task.state {
            case .pending:
                stop = true
            case .waiting(let continuation):
                task.state = .running
                continuation.resume()
                stop = true
            case .running, .cancelled:
                _storage.remove(task)
            }
        }
    }
}
