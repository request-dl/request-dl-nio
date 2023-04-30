/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals.Session {

    struct Configuration: Equatable {

        var secureConnection: Internals.SecureConnection?
        var redirectConfiguration: Internals.RedirectConfiguration?
        var timeout: Internals.Timeout = .init()
        var connectionPool: HTTPClient.Configuration.ConnectionPool = .init()
        var proxy: HTTPClient.Configuration.Proxy?
        var ignoreUncleanSSLShutdown: Bool = false
        var decompression: Internals.Decompression = .disabled
        var readingMode: Internals.Response.ReadingMode = .length(1_024)
        var dnsOverride: [String: String] = [:]
        var networkFrameworkWaitForConnectivity: Bool?
        var httpVersion: Internals.HTTPVersion?

        init() {}
    }
}

extension Internals.Session.Configuration {

    func build() throws -> HTTPClient.Configuration {
        var configuration = try HTTPClient.Configuration(
            tlsConfiguration: secureConnection?.build(),
            redirectConfiguration: redirectConfiguration?.build(),
            timeout: timeout.build(),
            connectionPool: connectionPool,
            proxy: proxy,
            ignoreUncleanSSLShutdown: ignoreUncleanSSLShutdown,
            decompression: decompression.build()
        )

        configuration.dnsOverride = dnsOverride

        if let flag = networkFrameworkWaitForConnectivity {
            configuration.networkFrameworkWaitForConnectivity = flag
        }

        if let httpVersion {
            configuration.httpVersion = httpVersion.build()
        }

        return configuration
    }
}
