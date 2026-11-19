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
    package final class PendingTasks: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()
        private let priority: _Concurrency.TaskPriority?

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

        /// - Parameter priority: The priority tracked work runs at. `nil`, the default, makes
        /// each piece of work inherit the priority of the context that starts it (see
        /// ``run(priority:_:)``), which is what work somebody ends up waiting for needs: a fixed
        /// low priority under load starves it behind the very callers that depend on it. Pass
        /// one only for work that really is background, such as a shutdown nobody waits for.
        package init(priority: _Concurrency.TaskPriority? = nil) {
            self.priority = priority
        }

        // MARK: - Internal methods

        /// Starts `operation` and tracks it until it finishes.
        ///
        /// - Parameter priority: Overrides the priority for this one operation. Without it, the
        /// operation runs at the priority given to ``init(priority:)`` or, when there is none, at
        /// the priority of the calling context. A caller that is not a task itself (an event
        /// loop callback, say) has no priority worth inheriting, and passes the one of the task
        /// it works for, captured while it was still running in that task.
        package func run(
            priority: _Concurrency.TaskPriority? = nil,
            _ operation: @escaping @Sendable () async -> Void
        ) {
            lock.withLock {
                _count += 1

                if _idleSignal == nil {
                    // Closing a signal only flips a flag, so it is safe under a lock.
                    _idleSignal = AsyncSignal()
                }
            }

            _Concurrency.Task(priority: priority ?? self.priority) {
                await operation()
                self.finish()
            }
        }

        /// Suspends until nothing is in flight.
        ///
        /// Loops rather than awaiting once: work started while the last of it is finishing
        /// opens a new epoch, and the caller has to wait for that one too.
        ///
        /// - Note: Returns early, without joining the current epoch, when the calling task is
        /// cancelled. `AsyncSignal.wait()` resolves near instantly once a task is already
        /// cancelled rather than genuinely suspending, so looping past that with `try?` would
        /// spin hot instead of idling until the real signal.
        package func waitUntilIdle() async {
            while let signal = lock.withLock({ _idleSignal }) {
                guard (try? await signal.wait()) != nil else {
                    return
                }
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
