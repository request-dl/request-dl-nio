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

        // MARK: - Internal methods

        package func build() -> HTTPClient.Configuration.Timeout {
            .init(
                connect: connect.map { .nanoseconds($0) },
                read: read.map { .nanoseconds($0) }
            )
        }
    }
}
