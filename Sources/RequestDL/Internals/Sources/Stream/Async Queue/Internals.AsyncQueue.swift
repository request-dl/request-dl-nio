//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Runs submitted operations one at a time, in submission order, off the caller's thread.
    ///
    /// Enqueueing is synchronous, which is what makes the order well defined: a caller's
    /// position is decided when it calls, not when a task it created happens to get scheduled.
    final class AsyncQueue: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()
        private let priority: _Concurrency.TaskPriority

        // MARK: - Unsafe properties

        private var _operations = FIFOQueue<@Sendable () async -> Void>()

        // Non nil exactly while the queue is running, and replaced on every busy epoch.
        //
        // A single long lived signal cannot work here. Closing it has to happen under the lock,
        // together with the state it describes, but opening it resumes continuations and so has
        // to happen outside. That ordering can invert, leaving the signal open while the queue
        // runs, and anyone in `waitUntilIdle` then spins hot. One signal per epoch removes the
        // inversion: a waiter released by the previous epoch simply picks up the current one.
        private var _idleSignal: AsyncSignal?

        // MARK: - Inits

        init(priority: _Concurrency.TaskPriority = .utility) {
            self.priority = priority
        }

        // MARK: - Internal methods

        func addOperation(_ operation: @escaping @Sendable () async -> Void) {
            let didStart = lock.withLock { () -> Bool in
                _operations.append(operation)

                guard _idleSignal == nil else {
                    return false
                }

                // Closing a signal only flips a flag, so it is safe to do while holding a lock.
                _idleSignal = AsyncSignal()
                return true
            }

            guard didStart else {
                return
            }

            runNext()
        }

        /// Suspends until the queue has drained.
        ///
        /// Loops rather than awaiting once: an operation submitted while the queue is going
        /// idle opens a new epoch, and the caller has to wait for that one too.
        ///
        /// - Note: Returns early, without joining the current epoch, when the calling task is
        /// cancelled. `AsyncSignal.wait()` resolves near instantly once a task is already
        /// cancelled rather than genuinely suspending, so looping past that with `try?` would
        /// spin hot instead of idling until the real signal.
        func waitUntilIdle() async {
            while let signal = lock.withLock({ _idleSignal }) {
                guard (try? await signal.wait()) != nil else {
                    return
                }
            }
        }

        // MARK: - Private methods

        private func runNext() {
            let next = lock.withLock { () -> (operation: (@Sendable () async -> Void)?, idle: AsyncSignal?) in
                if let operation = _operations.popFirst() {
                    return (operation, nil)
                }

                let signal = _idleSignal
                _idleSignal = nil
                return (nil, signal)
            }

            guard let operation = next.operation else {
                // Outside the critical section: this resumes continuations.
                next.idle?.signal()
                return
            }

            _Concurrency.Task(priority: priority) {
                await operation()
                self.runNext()
            }
        }
    }
}
