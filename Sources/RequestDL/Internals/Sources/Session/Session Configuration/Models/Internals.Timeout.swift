/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    struct Timeout: Sendable, Hashable {

        // MARK: - Internal properties

        var connect: UnitTime?

        var read: UnitTime?

        // MARK: - Internal methods

        func build() -> HTTPClient.Configuration.Timeout {
            .init(
                connect: connect?.build(),
                read: read?.build()
            )
        }
    }
}
