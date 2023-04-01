/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals.Session {

    struct Configuration {

        var secureConnection: Internals.SecureConnection?
        var redirectConfiguration: HTTPClient.Configuration.RedirectConfiguration?
        var timeout: HTTPClient.Configuration.Timeout = .init()
        var connectionPool: HTTPClient.Configuration.ConnectionPool = .init()
        var proxy: HTTPClient.Configuration.Proxy?
        var ignoreUncleanSSLShutdown: Bool = false
        var decompression: HTTPClient.Decompression = .disabled
        var readingMode: Internals.Response.ReadingMode = .length(1_024)

        private var updatingKeyPaths: ((inout HTTPClient.Configuration) -> Void)?

        init() {}

        mutating func setValue<Value>(
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

extension Internals.Session.Configuration {

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
