/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// A structure representing the head of an HTTP response.
public struct ResponseHead: Sendable, Hashable {

    /// A structure representing the status of an HTTP response.
    public struct Status: Sendable, Hashable, CustomDebugStringConvertible {

        // MARK: - Public properties

        public var debugDescription: String {
            String(code) + " " + reason
        }

        /// The HTTP status code of the response.
        public let code: UInt

        /// The reason phrase associated with the HTTP status code.
        public let reason: String

        // MARK: - Inits

        /**
         Initializes the status of HTTP response.
        
         - Parameters:
           - code: The HTTP status code of the response.
           - reason: The reason phrase associated with the HTTP status code.
        */
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

    /// A structure representing the version of the HTTP protocol used in an HTTP response.
    public struct Version: Sendable, Hashable, CustomDebugStringConvertible {

        // MARK: - Public properties

        public var debugDescription: String {
            String(minor) + " ... " + String(major)
        }

        /// The minor version number of the HTTP protocol used in the response.
        public let minor: Int

        /// The major version number of the HTTP protocol used in the response.
        public let major: Int

        // MARK: - Inits

        /**
         Initializes the version of HTTP response.
        
         - Parameters:
           - minor: The minor version number of the HTTP protocol used in the response.
           - major: The major version number of the HTTP protocol used in the response.
         */
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

    // MARK: - Public properties

    /// The URL of the response.
    public let url: URL?

    /// The status of the response.
    public let status: Status

    /// The version of the HTTP protocol used in the response.
    public let version: Version

    /// The headers of the response.
    public let headers: HTTPHeaders

    /// A boolean value indicating whether the connection should be kept alive after the response.
    public let isKeepAlive: Bool

    // MARK: - Inits

    /**
     Initializes the head of a HTTP response.

     - Parameters:
        - url: The URL of the response.
        - status: The status of the response.
        - version: The version of the HTTP protocol used in the response.
        - headers: The headers of the response.
        - isKeepAlive: A boolean value indicating whether the connection should be kept alive after the response.
     */
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
            headers: head.headers,
            isKeepAlive: head.isKeepAlive
        )
    }
}

// MARK: - CustomDebugStringConvertible

extension ResponseHead: CustomDebugStringConvertible {

    public var debugDescription: String {
        """
        \(url?.absoluteString ?? "URL(nil)")
        \(status.debugDescription) Status

        HTTP version range: \(version)
        Keep alive: \(isKeepAlive)

        \(headers.debugDescription)
        """
    }
}
