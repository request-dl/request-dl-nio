/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct ResponseHead: Sendable, Codable, Hashable {
        let url: String
        let status: Status
        let version: Version
        let headers: Headers
        let isKeepAlive: Bool
    }
}

extension Internals.ResponseHead {

    struct Version: Sendable, Codable, Hashable {
        let minor: Int
        let major: Int
    }

    struct Status: Sendable, Codable, Hashable {
        let code: UInt
        let reason: String
    }
}
