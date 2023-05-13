/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct ResponseHead: Hashable {
        let url: String
        let status: Status
        let version: Version
        let headers: Headers
        let isKeepAlive: Bool
    }
}

extension Internals.ResponseHead {

    struct Version: Hashable {
        let minor: Int
        let major: Int
    }

    struct Status: Hashable {
        let code: UInt
        let reason: String
    }
}
