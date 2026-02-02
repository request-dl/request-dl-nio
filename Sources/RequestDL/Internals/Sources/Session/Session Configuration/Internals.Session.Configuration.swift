/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals.Session {

    struct Configuration: Sendable, Equatable {

        // MARK: - Internal properties

        var secureConnection: Internals.SecureConnection?
        var redirectConfiguration: Internals.RedirectConfiguration?
        var timeout: Internals.Timeout = .init()
        var connectionPool: HTTPClient.Configuration.ConnectionPool = .init()
        var proxy: Internals.Proxy?
        var ignoreUncleanSSLShutdown: Bool = false
        var decompression: Internals.Decompression = .disabled
        var dnsOverride: [String: String] = [:]
        var networkFrameworkWaitForConnectivity: Bool?
        var httpVersion: Internals.HTTPVersion?
        var enableNetworkFramework: Bool = false

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func build() throws -> HTTPClient.Configuration {
            let secureConnectionOutput = try secureConnection?.build()

            var configuration = HTTPClient.Configuration(
                tlsConfiguration: secureConnectionOutput?.tlsConfiguration,
                tlsPinning: secureConnectionOutput?.tlsPinning,
                redirectConfiguration: redirectConfiguration?.build(),
                timeout: timeout.build(),
                connectionPool: connectionPool,
                proxy: proxy?.build(),
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
}

extension Internals.Session.Configuration {

    var isCompatibleWithNetworkFramework: Bool {
        if enableNetworkFramework {
            return secureConnection?.isCompatibleWithNetworkFramework ?? true
        }

        return false
    }
}
