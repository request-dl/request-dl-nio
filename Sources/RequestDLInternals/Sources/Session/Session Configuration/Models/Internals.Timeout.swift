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
        package var read: Int64?

        /// Nanoseconds, matching `UnitTime.nanoseconds` (`RequestDL`'s public unit of time).
        ///
        /// Unlike `connect`/`read`, this isn't part of `HTTPClient.Configuration.Timeout`: no
        /// AsyncHTTPClient knob covers a resource-wide deadline, so `build()` below doesn't
        /// forward it. `RawTask` reads it directly to drive `Internals.ResourceDeadline` instead.
        package var resource: Int64?

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> HTTPClient.Configuration.Timeout {
            .init(
                connect: connect.map { .nanoseconds($0) },
                read: read.map { .nanoseconds($0) }
            )
        }
        #endif

        // MARK: - Hashable

        // Hand-written rather than synthesized, deliberately excluding `resource`: this struct
        // feeds `Internals.Session.Configuration`'s `Hashable`/`==`, which is
        // `Internals.ClientManager`'s pooled-client cache key, and `resource` is never read by
        // `build()` above (`RawTask` reads it directly instead). Including it meant two sessions
        // identical in every way `build()` actually consumes — differing only in
        // `.timeout(.resource(_:))` — produced byte-identical `HTTPClient.Configuration`s but
        // still compared unequal, so they could never share a pooled client/connection pool.
        package static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.connect == rhs.connect && lhs.read == rhs.read
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(connect)
            hasher.combine(read)
        }
    }
}
