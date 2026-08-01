//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Tracks unstructured work so somebody can wait for all of it to finish.
    ///
    /// Deliberately **not** an ``AsyncQueue``. The operations tracked here run for as long as
    /// the response body they are consuming, so serializing them would let one slow download
    /// block every unrelated write behind it. They run concurrently, exactly as before; the
    /// only thing added is the ability to join them.
    final class PendingTasks: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()
        private let priority: _Concurrency.TaskPriority

        // MARK: - Unsafe properties

        private var _count = 0

        // Non nil exactly while work is in flight, and replaced on every busy epoch.
        //
        // A single long lived signal cannot work. Closing it belongs under the lock, together
        // with the count it describes, but opening it resumes continuations and so has to
        // happen outside. That ordering can invert, leaving the signal open while work is still
        // running, and anyone waiting then spins hot. One signal per epoch removes the
        // inversion: a waiter released by the previous epoch simply picks up the current one.
        private var _idleSignal: AsyncSignal?

        // MARK: - Inits

        init(priority: _Concurrency.TaskPriority = .background) {
            self.priority = priority
        }

        // MARK: - Internal methods

        func run(_ operation: @escaping @Sendable () async -> Void) {
            lock.withLock {
                _count += 1

                if _idleSignal == nil {
                    // Closing a signal only flips a flag, so it is safe under a lock.
                    _idleSignal = AsyncSignal()
                }
            }

            _Concurrency.Task(priority: priority) {
                await operation()
                self.finish()
            }
        }

        /// Suspends until nothing is in flight.
        ///
        /// Loops rather than awaiting once: work started while the last of it is finishing
        /// opens a new epoch, and the caller has to wait for that one too.
        func waitUntilIdle() async {
            while let signal = lock.withLock({ _idleSignal }) {
                try? await signal.wait()
            }
        }

        // MARK: - Private methods

        private func finish() {
            let signal = lock.withLock { () -> AsyncSignal? in
                _count -= 1

                guard _count == .zero else {
                    return nil
                }

                let signal = _idleSignal
                _idleSignal = nil
                return signal
            }

            // Outside the critical section: this resumes continuations.
            signal?.signal()
        }
    }
}
