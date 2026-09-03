//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient

extension Internals {

    package struct Timeout: Sendable, Hashable {

        // MARK: - Internal properties

        /// Nanoseconds, matching `UnitTime.nanoseconds` -- `RequestDL`'s public unit of time.
        package var connect: Int64?

        /// Nanoseconds, matching `UnitTime.nanoseconds` -- `RequestDL`'s public unit of time.
        package var read: Int64?

        /// Nanoseconds, matching `UnitTime.nanoseconds` -- `RequestDL`'s public unit of time.
        ///
        /// Unlike `connect`/`read`, this isn't part of `HTTPClient.Configuration.Timeout` -- no
        /// AsyncHTTPClient knob covers a resource-wide deadline, so `build()` below doesn't
        /// forward it. `RawTask` reads it directly to drive `Internals.ResourceDeadline` instead.
        package var resource: Int64?

        // MARK: - Internal methods

        package func build() -> HTTPClient.Configuration.Timeout {
            .init(
                connect: connect.map { .nanoseconds($0) },
                read: read.map { .nanoseconds($0) }
            )
        }
    }
}
