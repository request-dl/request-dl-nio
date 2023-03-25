/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Session {

    public struct Configuration {

        public var secureConnection: Session.SecureConnection?
        public var redirectConfiguration: RedirectConfiguration?
        public var timeout: Timeout = .init()
        public var connectionPool: ConnectionPool = .init()
        public var proxy: Proxy?
        public var ignoreUncleanSSLShutdown: Bool = false
        public var decompression: Decompression = .disabled
        public var readingMode: Response.ReadingMode = .length(1_024)

        private var updatingKeyPaths: ((inout HTTPClient.Configuration) -> Void)?

        public init() {}

        public mutating func setValue<Value>(
            _ value: Value,
            forKey keyPath: WritableKeyPath<HTTPClient.Configuration, Value>
        ) {
            let old = updatingKeyPaths
            updatingKeyPaths = {
                old?(&$0)
                $0[keyPath: keyPath] = value
            }
        }
    }
}

extension Session.Configuration {

    func build() throws -> HTTPClient.Configuration {
        var configuration = HTTPClient.Configuration(
            tlsConfiguration: try secureConnection?.build(),
            redirectConfiguration: redirectConfiguration,
            timeout: timeout,
            connectionPool: connectionPool,
            proxy: proxy,
            ignoreUncleanSSLShutdown: ignoreUncleanSSLShutdown,
            decompression: decompression
        )

        updatingKeyPaths?(&configuration)

        return configuration
    }
}

extension Session {

    public typealias Decompression = HTTPClient.Decompression
}

extension Session.Configuration {

    public typealias RedirectConfiguration = HTTPClient.Configuration.RedirectConfiguration

    public typealias Timeout = HTTPClient.Configuration.Timeout

    public typealias ConnectionPool = HTTPClient.Configuration.ConnectionPool

    public typealias Proxy = HTTPClient.Configuration.Proxy
}

import NIOHTTPCompression

extension Session.Decompression {

    public typealias Limit = NIOHTTPDecompression.DecompressionLimit
}
