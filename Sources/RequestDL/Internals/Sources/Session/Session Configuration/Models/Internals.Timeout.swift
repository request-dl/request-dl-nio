/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    struct Timeout: Hashable {

        var connect: UnitTime?

        var read: UnitTime?
    }
}

extension Internals.Timeout {

    func build() -> HTTPClient.Configuration.Timeout {
        .init(
            connect: connect?.build(),
            read: read?.build()
        )
    }
}
