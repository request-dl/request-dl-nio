//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
#if canImport(Darwin)
import struct Foundation.DispatchTime
#endif
#endif

extension Internals {

    /// How long one execution may go without a byte moving in either direction, enforced by
    /// RequestDL itself on every executor: `Timeout(_:for: .read)`.
    ///
    /// The transports each have a timer of their own, and they disagree about what idle means:
    /// `timeoutIntervalForRequest` covers an upload and a download and is reset by any byte,
    /// AsyncHTTPClient's read timeout covers a download only, and both go on counting while the
    /// application has suspended the transfer or has not yet read what already arrived. Those
    /// timers are turned off, and this one is fed by what every executor already reports to
    /// `Internals.ExecutionObserver`: a byte of the request body sent, a byte of the response
    /// received, the head, a reconnection.
    ///
    /// ## What does not count as idle
    ///
    /// Time during which the client is the one holding the exchange back: suspended through a
    /// `RequestController`, or with the response window shut because whoever reads the body has
    /// not caught up. Nothing is expected from the server then, so nothing is owed by it. See
    /// ``hold(while:)``.
    ///
    /// ## How it ends an execution
    ///
    /// Once the budget is spent the deadline cancels the request's ``Internals/TaskSeed``, as
    /// if the caller had dropped the response, and from then on ``isExpired`` is `true`: whoever
    /// is waiting on the request sees it fail, and reads ``isExpired`` to tell this ending from
    /// a cancellation of the caller's own.
    ///
    /// One instance per execution. The watcher runs only between ``start()`` and ``finish()``,
    /// and costs a single task that wakes up once per budget, not once per byte: ``touch()`` is
    /// a store under a lock.
    package final class IdleDeadline: @unchecked Sendable {

        // MARK: - Internal properties

        /// The budget, in nanoseconds.
        package let nanoseconds: Int64

        /// Whether the budget ran out. Never goes back to `false`.
        package var isExpired: Bool {
            lock.withLock { _isExpired }
        }

        /// The task counting, from ``start()`` until it ends: what a test waits for to know the
        /// deadline is done.
        package var watcher: Task<Void, Never>? {
            lock.withLock { _watcher }
        }

        // MARK: - Private properties

        private let now: @Sendable () -> UInt64
        private let sleep: @Sendable (UInt64) async throws -> Void
        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _lastActivity: UInt64
        private var _isExpired = false
        private var _isFinished = false
        private var _isHeld: (@Sendable () -> Bool)?
        private weak var _seed: Internals.TaskSeed?
        private var _wasAttached = false
        private var _watcher: Task<Void, Never>?

        // MARK: - Inits

        /// - Parameter nanoseconds: What `Internals.Timeout.read` says. ``make(nanoseconds:)`` is
        /// what turns "never" into no deadline at all.
        /// - Parameter now: The monotonic clock, in nanoseconds. A test replaces it to move time.
        /// - Parameter sleep: Waits that many nanoseconds. A test replaces it to control when the
        /// watcher wakes up.
        package init(
            nanoseconds: Int64,
            now: @escaping @Sendable () -> UInt64 = IdleDeadline.monotonicNow,
            sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
        ) {
            self.nanoseconds = max(nanoseconds, .zero)
            self.now = now
            self.sleep = sleep
            self._lastActivity = now()
        }

        // MARK: - Internal static methods

        /// Anything at or above this means "never": `UnitTime.infinity`.
        package static let never = Int64.max

        /// What a deadline reads time and waits with.
        package struct Clock: Sendable {

            package let now: @Sendable () -> UInt64
            package let sleep: @Sendable (UInt64) async throws -> Void

            package init(
                now: @escaping @Sendable () -> UInt64,
                sleep: @escaping @Sendable (UInt64) async throws -> Void
            ) {
                self.now = now
                self.sleep = sleep
            }

            package static let system = Clock(
                now: IdleDeadline.monotonicNow,
                sleep: { try await Task.sleep(nanoseconds: $0) }
            )
        }

        /// The clock the deadlines made by ``make(nanoseconds:)`` use: the machine's, unless a test
        /// binds its own, so that what runs out and when does not depend on how fast the machine
        /// happens to be running (a test that waits for a second of real time to pass fails
        /// whenever the machine stalls for one).
        @TaskLocal package static var clock: Clock = .system

        /// The deadline for `nanoseconds` of idle, or `nil` when the budget is `Int64.max`, which
        /// is how a caller says it does not want one.
        package static func make(nanoseconds: Int64) -> IdleDeadline? {
            guard nanoseconds < Self.never else {
                return nil
            }

            let clock = Self.clock
            return IdleDeadline(nanoseconds: nanoseconds, now: clock.now, sleep: clock.sleep)
        }

        package static func monotonicNow() -> UInt64 {
            #if canImport(Darwin)
            // Monotonic and not advancing while the device sleeps, the same clock
            // `Internals.ResourceDeadline` measures with.
            return DispatchTime.now().uptimeNanoseconds
            #else
            let elapsed = ContinuousClock.now - reference
            let (seconds, attoseconds) = elapsed.components
            return UInt64(clamping: seconds) &* 1_000_000_000 &+ UInt64(clamping: attoseconds / 1_000_000_000)
            #endif
        }

        #if !canImport(Darwin)
        private static let reference = ContinuousClock.now
        #endif

        // MARK: - Internal methods

        /// Says what holds the exchange back on the client's side, so that time is not idle.
        ///
        /// Asked from the watcher, never under this object's lock, so `isHeld` may take locks of
        /// its own.
        package func hold(while isHeld: @escaping @Sendable () -> Bool) {
            lock.withLock {
                _isHeld = isHeld
            }
        }

        /// Something moved: a byte, the head, a resumption. Starts the budget over.
        package func touch() {
            let instant = now()

            lock.withLock {
                guard !_isFinished, !_isExpired else {
                    return
                }

                _lastActivity = instant
            }
        }

        /// The request the deadline ends once the budget is spent. Held weakly: a `TaskSeed` that
        /// goes away cancels the request by itself, and must not be kept alive by a timer.
        ///
        /// A deadline that ran out before the request existed ends it now.
        package func attach(_ seed: Internals.TaskSeed) {
            let expired = lock.withLock { () -> Bool in
                _seed = seed
                _wasAttached = true
                return _isExpired
            }

            if expired {
                seed()
            }
        }

        /// Starts counting, from now.
        package func start() {
            lock.withLock {
                guard _watcher == nil, !_isFinished else {
                    return
                }

                _lastActivity = now()
                _watcher = Task.detached { [self] in
                    await watch()
                }
            }
        }

        /// The exchange is over, whichever way: nothing is left to time.
        package func finish() {
            let watcher = lock.withLock { () -> Task<Void, Never>? in
                _isFinished = true
                return _watcher
            }

            watcher?.cancel()
        }

        // MARK: - Private methods

        private func watch() async {
            while !Task.isCancelled {
                let isHeld = lock.withLock { _isHeld }

                // Asked outside the lock: what holds an exchange back is a window or a control
                // with locks of its own, which may be calling `touch()` from under them.
                let held = isHeld?() ?? false

                let wait = lock.withLock { () -> UInt64? in
                    // A request whose seed is gone is gone too.
                    guard !_isFinished, !_wasAttached || _seed != nil else {
                        return nil
                    }

                    let instant = now()

                    if held {
                        // The client is the one holding things back: the budget starts over, and
                        // is looked at again a full budget from now.
                        _lastActivity = instant
                    }

                    let due = _lastActivity &+ UInt64(nanoseconds)

                    guard instant >= due else {
                        return due - instant
                    }

                    _isExpired = true
                    return 0
                }

                guard let wait else {
                    return
                }

                guard wait > 0 else {
                    expire()
                    return
                }

                do {
                    try await sleep(wait)
                } catch {
                    return
                }
            }
        }

        private func expire() {
            let seed = lock.withLock { _seed }
            seed?()
        }
    }
}
