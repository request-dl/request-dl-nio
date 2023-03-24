//
//  File.swift
//
//
//  Created by Brenno on 20/03/23.
//

import Foundation
import RequestDLInternals

public struct ResponseHead: Equatable {

    public let status: Status
    public let version: Version
    public let headers: [String: String]
    public let isKeepAlive: Bool

    public init(
        status: Status,
        version: Version,
        headers: [String: String],
        isKeepAlive: Bool
    ) {
        self.status = status
        self.version = version
        self.headers = headers
        self.isKeepAlive = isKeepAlive
    }

    init(_ head: RequestDLInternals.ResponseHead) {
        self.init(
            status: .init(head.status),
            version: .init(head.version),
            headers: Dictionary(Array(head.headers)) { key, _ in key },
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

        init(_ status: RequestDLInternals.ResponseHead.Status) {
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

        init(_ version: RequestDLInternals.ResponseHead.Version) {
            self.init(
                minor: version.minor,
                major: version.major
            )
        }
    }
}
