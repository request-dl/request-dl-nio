//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import NIOHTTPCompression

extension Internals.Session {

    package struct Configuration: Sendable, Equatable {

        // MARK: - Internal properties

        package var secureConnection: Internals.SecureConnection?
        package var redirectConfiguration: Internals.RedirectConfiguration?
        package var timeout: Internals.Timeout = .init()
        package var connectionPool: HTTPClient.Configuration.ConnectionPool = .init()
        package var proxy: Internals.Proxy?
        package var decompression: Internals.Decompression = .disabled
        package var compression: Internals.Compression = .disabled
        package var dnsOverride: [String: String] = [:]
        package var networkFrameworkWaitForConnectivity: Bool?
        package var httpVersion: Internals.HTTPVersion?
        package var enableNetworkFramework: Bool = false

        // MARK: - Inits

        package init() {}

        // MARK: - Internal methods

        package func build() throws -> HTTPClient.Configuration {
            let secureConnectionOutput = try secureConnection?.build()

            var configuration = HTTPClient.Configuration.init(
                tlsConfiguration: secureConnectionOutput?.tlsConfiguration,
                tlsPinning: secureConnectionOutput?.tlsPinning,
                redirectConfiguration: redirectConfiguration?.build(),
                timeout: timeout.build(),
                connectionPool: connectionPool,
                proxy: proxy?.build(),
                decompression: decompression.build(),
                tracing: .init()
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

    package var isCompatibleWithNetworkFramework: Bool {
        if enableNetworkFramework {
            return secureConnection?.isCompatibleWithNetworkFramework ?? true
        }

        return false
    }
}
