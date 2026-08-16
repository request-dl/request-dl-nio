//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import NIOHTTPCompression

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
        var compression: Internals.Compression = .disabled
        var dnsOverride: [String: String] = [:]
        var networkFrameworkWaitForConnectivity: Bool?
        var httpVersion: Internals.HTTPVersion?
        var enableNetworkFramework: Bool = false

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func build() throws -> HTTPClient.Configuration {
            var configuration = try HTTPClient.Configuration(
                tlsConfiguration: secureConnection?.build(),
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

            if case .enabled(let algorithm) = compression {
                let encoding = algorithm.build()

                // `NIOHTTPRequestCompressor` is deliberately not `Sendable` (mutable per-connection
                // compression state), so it can only be added via the synchronous pipeline API, which
                // requires running on the channel's own event loop. AsyncHTTPClient doesn't guarantee
                // this debug initializer runs there, hence the explicit `submit`.
                configuration.http1_1ConnectionDebugInitializer = { channel in
                    channel.eventLoop.submit {
                        let sync = channel.pipeline.syncOperations
                        let requestEncoderContext = try sync.context(handlerType: HTTPRequestEncoder.self)

                        try sync.addHandler(
                            NIOHTTPRequestCompressor(encoding: encoding),
                            position: .after(requestEncoderContext.handler)
                        )
                    }
                }
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
