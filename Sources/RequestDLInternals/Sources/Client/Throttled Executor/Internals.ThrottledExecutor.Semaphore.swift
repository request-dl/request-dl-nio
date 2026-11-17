//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals.ThrottledExecutor {

    /// A counting semaphore whose waiters can leave the queue.
    ///
    /// `AsyncSemaphore` is "cancellation transparent" on purpose: a waiter that is cancelled still takes
    /// its turn, runs, and hands its permit back, which is what makes it safe for code that cannot do
    /// without the permit. Here, the permits are held by requests that can stay in flight for as long as
    /// the server likes, and the waiter is a request nobody wants anymore, so being made to wait for a
    /// slot that it is going to give straight back is the worst of both: it stays stuck behind the
    /// requests ahead of it, and whoever is behind it waits one more hand-off.
    ///
    /// A cancelled waiter leaves the queue and throws `CancellationError`. Order is untouched for
    /// everyone else: waiters are served first in, first out, and a permit goes straight to the first
    /// of them rather than back to the count to be raced for.
    package final class Semaphore: @unchecked Sendable {

        // MARK: - Inner types

        /// One suspended caller. Linked to its neighbours so that joining, leaving and being served are
        /// all constant time however many are queued, which a limit of one under a burst of requests
        /// makes a long queue.
        private final class Waiter: @unchecked Sendable {

            enum State {
                /// Not in the queue yet, and not cancelled.
                case idle
                case waiting(UnsafeContinuation<Void, any Error>)
                case granted
                case cancelled
            }

            var state = State.idle
            var previous: Waiter?
            var next: Waiter?
        }

        // MARK: - Package properties

        /// Permits currently available.
        package var availablePermits: Int {
            lock.withLock { _permits }
        }

        /// Callers currently waiting for a permit.
        package var waitingCount: Int {
            lock.withLock { _waitingCount }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _permits: Int
        private var _waitingCount = 0
        private var _head: Waiter?
        private var _tail: Waiter?

        // MARK: - Inits

        /// - Parameter permits: How many callers may hold a permit at the same time. Must be positive:
        /// zero could never be acquired, and `ThrottledExecutor` turns a non-positive limit into no
        /// semaphore at all.
        package init(permits: Int) {
            precondition(permits > .zero, "Semaphore needs at least one permit")
            _permits = permits
        }

        // MARK: - Package methods

        /// Suspends until a permit is available, and takes it.
        ///
        /// - Throws: `CancellationError` if the current task is cancelled before it was handed a permit,
        /// including when it was cancelled before asking. No permit is taken in that case.
        package func wait(isolation: isolated (any Actor)? = #isolation) async throws {
            let waiter = Waiter()

            try await withTaskCancellationHandler(
                operation: {
                    try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
                        let outcome = lock.withLock { () -> Outcome in
                            // `onCancel` can run before this does, even before the task got here at all.
                            if case .cancelled = waiter.state {
                                return .cancelled
                            }

                            if _permits > .zero {
                                _permits -= 1
                                waiter.state = .granted
                                return .granted
                            }

                            waiter.state = .waiting(continuation)
                            enqueue(waiter)
                            return .suspended
                        }

                        switch outcome {
                        case .granted:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .suspended:
                            break
                        }
                    }
                },
                onCancel: {
                    let continuation = lock.withLock { () -> UnsafeContinuation<Void, any Error>? in
                        switch waiter.state {
                        case .idle:
                            waiter.state = .cancelled
                            return nil
                        case .waiting(let continuation):
                            dequeue(waiter)
                            waiter.state = .cancelled
                            return continuation
                        case .granted, .cancelled:
                            // Already holds a permit, which is the caller's to give back.
                            return nil
                        }
                    }

                    continuation?.resume(throwing: CancellationError())
                },
                isolation: isolation
            )
        }

        /// Returns a permit, handing it to the first caller waiting for one.
        package func signal() {
            let continuation = lock.withLock { () -> UnsafeContinuation<Void, any Error>? in
                guard let waiter = _head else {
                    _permits += 1
                    return nil
                }

                dequeue(waiter)

                guard case .waiting(let continuation) = waiter.state else {
                    preconditionFailure("A queued waiter is always suspended")
                }

                waiter.state = .granted
                return continuation
            }

            continuation?.resume()
        }

        // MARK: - Private methods

        private enum Outcome {
            case granted
            case cancelled
            case suspended
        }

        /// - Warning: Lockless. The caller must be holding ``lock``.
        private func enqueue(_ waiter: Waiter) {
            waiter.previous = _tail

            if let tail = _tail {
                tail.next = waiter
            } else {
                _head = waiter
            }

            _tail = waiter
            _waitingCount += 1
        }

        /// - Warning: Lockless. The caller must be holding ``lock``.
        private func dequeue(_ waiter: Waiter) {
            if let previous = waiter.previous {
                previous.next = waiter.next
            } else {
                _head = waiter.next
            }

            if let next = waiter.next {
                next.previous = waiter.previous
            } else {
                _tail = waiter.previous
            }

            waiter.previous = nil
            waiter.next = nil
            _waitingCount -= 1
        }
    }
}

// MARK: - Testing

@_spi(Testing)
extension Internals.ThrottledExecutor.Semaphore {

    /// Suspends until ``waitingCount`` is `count`.
    ///
    /// Same reason as `AsyncSemaphore.waitForWaiters(_:timeout:)`: task creation order is not task arrival
    /// order, so a test that needs `count` callers queued has to look, not guess. Polled rather than
    /// notified, which nothing in the queue itself would have a use for.
    ///
    /// - Throws: `WaitTimeoutError` if the count did not settle within `timeout` seconds.
    package func waitForWaiters(_ count: Int, timeout: Double = 2) async throws {
        for _ in 0..<Int(timeout * 1_000) {
            if waitingCount == count {
                return
            }

            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000)
        }

        throw WaitTimeoutError(expected: count, actual: waitingCount)
    }

    package struct WaitTimeoutError: Error, CustomStringConvertible {
        package let expected: Int
        package let actual: Int

        package var description: String {
            "Expected \(expected) waiting callers, found \(actual)"
        }
    }
}
