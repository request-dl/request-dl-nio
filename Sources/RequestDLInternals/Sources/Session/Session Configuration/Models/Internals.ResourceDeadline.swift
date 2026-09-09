//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
#if canImport(Darwin)
import struct Foundation.DispatchTime
#endif
#endif

extension Internals {

    /// Races one async operation against ``Timeout/Source/resource``'s deadline -- unlike
    /// `connect`/`read` (per-phase timeouts AsyncHTTPClient enforces on its own), a resource
    /// timeout bounds the whole request end to end (connection, redirects, and the entire body
    /// transfer), the same way `URLSessionConfiguration.timeoutIntervalForResource` does.
    /// Nothing in AsyncHTTPClient or `Internals.URLSessionClient` offers that as a single knob,
    /// so `RawTask` applies it itself, racing both the initial connect/redirect phase and every
    /// subsequent body read against the same deadline.
    package struct ResourceDeadline: Sendable {

        // MARK: - Private properties

        // Monotonic, not wall clock -- same rationale as `Internals.Storage`/`Internals.ClientManager`:
        // a `Date`-based deadline moves if the user or NTP moves the system clock, and this must not
        // advance while the device is suspended either way. `ContinuousClock` needs macOS 13/iOS 16/
        // tvOS 16/watchOS 9, newer than this package's macOS 12/iOS 15/tvOS 15/watchOS 8 floor, so
        // Darwin uses `DispatchTime.now().uptimeNanoseconds` instead; everywhere else already gets
        // `ContinuousClock` at whatever Swift version is available.
        #if canImport(Darwin)
        private let deadlineUptimeNanoseconds: UInt64?
        #else
        private let instant: ContinuousClock.Instant?
        #endif

        // MARK: - Inits

        /// - Parameter nanoseconds: `Internals.Timeout.resource`, measured from *now*. `nil`
        /// disables racing entirely, so `race(seed:_:)` becomes a plain `await` with no task-group
        /// overhead -- the case every request without `.resource` configured takes.
        package init(nanoseconds: Int64?) {
            #if canImport(Darwin)
            deadlineUptimeNanoseconds = nanoseconds.map { DispatchTime.now().uptimeNanoseconds &+ UInt64($0) }
            #else
            instant = nanoseconds.map { ContinuousClock.now.advanced(by: .nanoseconds($0)) }
            #endif
        }

        // MARK: - Internal methods

        /// Runs `operation`, cancelling it (and `seed`, if given) and throwing
        /// ``ResourceTimeoutError`` if the deadline passes first.
        ///
        /// - Parameter seed: Cancelled on timeout in addition to `operation`'s own task --
        /// `operation`'s cancellation alone only stops *this* particular await; a `TaskSeed` is
        /// what actually tears down the underlying connection or stream, exactly as if the caller
        /// had cancelled or dropped the response themselves. `nil` before a `TaskSeed` exists yet
        /// (the initial connect/redirect phase, before `RawTask` has a `SessionTask` to cancel).
        package func race<T: Sendable>(
            seed: Internals.TaskSeed? = nil,
            _ operation: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            #if canImport(Darwin)
            guard let deadlineUptimeNanoseconds else {
                return try await operation()
            }

            // A deadline that's already passed before `operation` even starts must not race it --
            // `Task.sleep(nanoseconds: 0)` below still goes through a real scheduler hop, so a fast
            // enough `operation` (a loopback request under `.urlSession`, say) can win that race
            // and complete anyway, silently keeping a budget that was already spent. Checked here,
            // synchronously, so "already elapsed" is deterministic instead of a coin flip between
            // two child tasks' relative scheduling.
            guard DispatchTime.now().uptimeNanoseconds < deadlineUptimeNanoseconds else {
                seed?()
                throw ResourceTimeoutError()
            }
            #else
            guard let instant else {
                return try await operation()
            }

            guard ContinuousClock.now < instant else {
                seed?()
                throw ResourceTimeoutError()
            }
            #endif

            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }

                group.addTask {
                    #if canImport(Darwin)
                    let now = DispatchTime.now().uptimeNanoseconds
                    let remaining = deadlineUptimeNanoseconds > now ? deadlineUptimeNanoseconds - now : 0
                    try await Task.sleep(nanoseconds: remaining)
                    #else
                    try await Task.sleep(until: instant, clock: .continuous)
                    #endif

                    seed?()
                    throw ResourceTimeoutError()
                }

                defer {
                    group.cancelAll()
                }

                return try await group.next()!
            }
        }
    }

    /// The internal marker `RawTask` catches and rewraps into `RequestDL`'s public
    /// `ResourceTimeoutError` -- mirrors the split `NetworkAvailabilityError`/
    /// `Internals.NetworkPathUnsatisfiedError` already uses.
    package struct ResourceTimeoutError: Swift.Error, Sendable {
        package init() {}
    }
}
