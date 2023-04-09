/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct ResponseHead: Equatable {
        let url: String
        let status: Status
        let version: Version
        let headers: Headers
        let isKeepAlive: Bool
    }
}

extension Internals.ResponseHead {

    struct Version: Equatable {
        let minor: Int
        let major: Int
    }

    struct Status: Equatable {
        let code: UInt
        let reason: String
    }
}
