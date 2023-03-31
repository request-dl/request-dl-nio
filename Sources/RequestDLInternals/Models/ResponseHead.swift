/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct ResponseHead: Equatable {
    public let url: String
    public let status: Status
    public let version: Version
    public let headers: Headers
    public let isKeepAlive: Bool
}

extension ResponseHead {

    public struct Version: Equatable {
        public let minor: Int
        public let major: Int
    }

    public struct Status: Equatable {
        public let code: UInt
        public let reason: String
    }
}
