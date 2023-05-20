/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOConcurrencyHelpers

struct AsyncLock: Sendable {

    private final class Storage: @unchecked Sendable {

        // MARK: - Private properties

        private let _lock = NIOLock()

        // MARK: - Unsafe properties

        private var _signal: Int = 1
        private var _tasks = [Task]()

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func wait() async {
            lock()

            _signal -= 1
            if _signal >= .zero {
                defer { unlock() }

                do {
                    try _Concurrency.Task.checkCancellation()
                } catch {
                    _signal += 1
                }

                return
            }

            let task = Task(.pending)

            return await withTaskCancellationHandler {
                await withUnsafeContinuation {
                    if case .cancelled = task.state {
                        unlock()
                        return
                    }

                    task.state = .waiting($0)
                    _tasks.insert(task, at: 0)
                    unlock()
                }
            } onCancel: {
                lock()

                _signal += 1

                if let index = _tasks.firstIndex(where: { $0 === task }) {
                    _tasks.remove(at: index)
                }

                if case .waiting = task.state {
                    unlock()
                } else {
                    task.state = .cancelled
                    unlock()
                }
            }
        }

        func signal() {
            lock()
            defer { unlock() }

            _signal += 1

            var pendingTasks = [Task]()
            var stop = false

            while !stop, let task = _tasks.popLast() {
                switch task.state {
                case .pending:
                    pendingTasks.append(task)
                case .waiting(let continuation):
                    continuation.resume()
                    stop = true
                case .cancelled:
                    break
                }
            }

            _tasks.append(contentsOf: pendingTasks.reversed())
        }

        // MARK: - Private methods

        func lock() {
            _lock.lock()
        }

        func unlock() {
            _lock.unlock()
        }

        deinit {
            precondition(_tasks.isEmpty, "The AsyncLock is being deallocated with pending tasks. This is not safe.")
        }
    }

    private final class Task: @unchecked Sendable {

        enum State {
            case pending
            case waiting(UnsafeContinuation<Void, Never>)
            case cancelled
        }

        var state: State

        init(_ state: State) {
            self.state = state
        }
    }

    // MARK: - Private properties

    private let storage = Storage()

    // MARK: - Inits

    init() {}

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
        await storage.wait()
    }

    func unlock() {
        storage.signal()
    }
}
