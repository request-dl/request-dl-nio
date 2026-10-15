//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

extension Internals {

    package struct Timeout: Sendable, Hashable {

        // MARK: - Internal properties

        /// Nanoseconds, matching `UnitTime.nanoseconds` (`RequestDL`'s public unit of time).
        package var connect: Int64?

        /// Nanoseconds, matching `UnitTime.nanoseconds` (`RequestDL`'s public unit of time).
        ///
        /// `nil` means "not configured", not "never": ``idle`` falls back to ``defaultRead``,
        /// as `URLSession`'s `timeoutIntervalForRequest` does. `Int64.max` is "never".
        ///
        /// Enforced by RequestDL itself on every executor (see `Internals.IdleDeadline`), not by
        /// the transports: `build()` and `buildURLSessionConfiguration()` turn their own timers
        /// off, because each one counts something different and none of them knows when the
        /// application is the one holding the exchange back.
        package var read: Int64?

        /// Nanoseconds, matching `UnitTime.nanoseconds` (`RequestDL`'s public unit of time).
        ///
        /// Unlike `connect`/`read`, this isn't part of `HTTPClient.Configuration.Timeout`: no
        /// AsyncHTTPClient knob covers a resource-wide deadline, so `build()` below doesn't
        /// forward it. `RawTask` reads it directly to drive `Internals.ResourceDeadline` instead.
        package var resource: Int64?

        /// The idle read timeout applied when `read` isn't set, in nanoseconds.
        ///
        /// AsyncHTTPClient has none by default, so a server that stops sending would hang a
        /// `.nio` request forever while `.urlSession` fails it after 60 s.
        package static let defaultRead: Int64 = 60_000_000_000

        /// How long an execution may go without a byte moving, in nanoseconds.
        package var idle: Int64 {
            read ?? Self.defaultRead
        }

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> HTTPClient.Configuration.Timeout {
            .init(
                connect: connect.map { .nanoseconds($0) },
                read: nil
            )
        }
        #endif

        // MARK: - Hashable

        // Hand-written rather than synthesized, deliberately excluding `resource` and `read`:
        // this struct feeds `Internals.Session.Configuration`'s `Hashable`/`==`, which is
        // `Internals.ClientManager`'s pooled-client cache key, and neither is read by `build()`
        // above (`RawTask` reads them directly instead). Including them would make two sessions
        // identical in every way `build()` actually consumes (differing only in
        // `.timeout(.resource(_:))` or `.timeout(.read(_:))`) produce byte-identical
        // `HTTPClient.Configuration`s that still compare unequal, so they could never share a
        // pooled client/connection pool.
        package static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.connect == rhs.connect
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(connect)
        }
    }
}
