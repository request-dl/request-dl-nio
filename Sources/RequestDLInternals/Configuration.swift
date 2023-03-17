/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Session {

    public struct Configuration {

        public var tlsConfiguration: TLSConfiguration?
        public var redirectConfiguration: RedirectConfiguration?
        public var timeout: Timeout = .init()
        public var connectionPool: ConnectionPool = .init()
        public var proxy: Proxy?
        public var ignoreUncleanSSLShutdown: Bool = false
        public var decompression: Decompression = .disabled

        public init() {}
    }
}

extension Session.Configuration {

    func build() -> HTTPClient.Configuration {
        HTTPClient.Configuration(
            tlsConfiguration: tlsConfiguration,
            redirectConfiguration: redirectConfiguration,
            timeout: timeout,
            connectionPool: connectionPool,
            proxy: proxy,
            ignoreUncleanSSLShutdown: ignoreUncleanSSLShutdown,
            decompression: decompression
        )
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
