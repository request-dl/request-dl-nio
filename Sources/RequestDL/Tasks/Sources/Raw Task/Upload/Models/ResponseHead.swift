/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct ResponseHead: Equatable {

    public let url: URL?
    public let status: Status
    public let version: Version
    public let headers: HTTPHeaders
    public let isKeepAlive: Bool

    public init(
        url: URL?,
        status: Status,
        version: Version,
        headers: HTTPHeaders,
        isKeepAlive: Bool
    ) {
        self.url = url
        self.status = status
        self.version = version
        self.headers = headers
        self.isKeepAlive = isKeepAlive
    }

    init(_ head: Internals.ResponseHead) {
        self.init(
            url: .init(string: head.url),
            status: .init(head.status),
            version: .init(head.version),
            headers: .init(head.headers),
            isKeepAlive: head.isKeepAlive
        )
    }
}

extension ResponseHead {

    public struct Status: Equatable {

        public let code: UInt
        public let reason: String

        public init(
            code: UInt,
            reason: String
        ) {
            self.code = code
            self.reason = reason
        }

        init(_ status: Internals.ResponseHead.Status) {
            self.init(
                code: status.code,
                reason: status.reason
            )
        }
    }

    public struct Version: Equatable {

        public let minor: Int
        public let major: Int

        public init(
            minor: Int,
            major: Int
        ) {
            self.minor = minor
            self.major = major
        }

        init(_ version: Internals.ResponseHead.Version) {
            self.init(
                minor: version.minor,
                major: version.major
            )
        }
    }
}
