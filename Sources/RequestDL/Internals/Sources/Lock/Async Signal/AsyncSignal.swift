/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct AsyncSignal: Sendable {

    private final class Storage: @unchecked Sendable {
        var signal = false
        var tasks: [Task] = []

        deinit {
            precondition(tasks.isEmpty, "The AsyncSignal is being deallocated with pending tasks. This is not safe.")
        }
    }

    private final class Task: @unchecked Sendable {

        enum State {
            case pending
            case waiting(UnsafeContinuation<Void, Never>)
            case running
            case cancelled
        }

        // MARK: - Internal properties

        var state: State

        // MARK: - Inits

        init(_ state: State) {
            self.state = state
        }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Internal properties

    private let _storage: Storage

    // MARK: - Inits

    init() {
        _storage = .init()
    }

    // MARK: - Internal methods

    func wait() async {
        lock.lock()

        if _storage.signal {
            lock.unlock()
            return
        }

        let task = Task(.pending)
        _storage.tasks.insert(task, at: .zero)
        lock.unlock()

        await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                lock.withLock {
                    if case .cancelled = task.state {
                        return
                    }

                    if _storage.signal {
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
                if let index = _storage.tasks.firstIndex(where: { $0 === task }) {
                    _storage.tasks.remove(at: index)
                }
            }
        }
    }

    func signal() {
        lock.withLock {
            guard !_storage.signal else {
                return
            }

            _storage.signal = true
            while let task = _storage.tasks.popLast() {
                if case .waiting(let continuation) = task.state {
                    task.state = .running
                    continuation.resume()
                }
            }
        }
    }
}
