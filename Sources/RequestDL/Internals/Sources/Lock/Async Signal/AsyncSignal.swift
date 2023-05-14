/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOConcurrencyHelpers

struct AsyncSignal: Sendable {

    private class Storage: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _isSignalProduced: Bool = false
        private var _tasks: [Task] = []

        // MARK: - Internal methods

        func wait() async {
            lock.lock()

            if _isSignalProduced {
                lock.unlock()
                return
            }

            return await withUnsafeContinuation {
                _tasks.append($0)
                lock.unlock()
            }
        }

        func signal() {
            lock.lock()
            defer { lock.unlock() }

            if !_isSignalProduced {
                _isSignalProduced = true
            }

            while let task = _tasks.popLast() {
                task.resume()
            }
        }

        deinit {
            precondition(_tasks.isEmpty, "The AsyncSignal is being deallocated with pending tasks. This is not safe.")
        }
    }

    typealias Task = UnsafeContinuation<Void, Never>

    // MARK: - Private properties

    private let storage: Storage

    // MARK: - Inits

    init() {
        self.storage = .init()
    }

    // MARK: - Internal methods

    func wait() async {
        await storage.wait()
    }

    func signal() {
        storage.signal()
    }
}
