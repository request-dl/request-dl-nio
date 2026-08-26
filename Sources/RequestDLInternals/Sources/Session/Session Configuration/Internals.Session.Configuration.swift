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
        package var ignoreUncleanSSLShutdown: Bool = false

        /// Defaults to unbounded auto-decompression on Apple platforms, matching URLSession's own
        /// behavior there — URLSession always decodes `Content-Encoding` transparently with no
        /// limit, and no way to turn it off. Matching that by default keeps this setting from
        /// silently diverging depending on which executor a request happens to run on. Off by
        /// default elsewhere, where URLSession isn't a runtime option and NIOHTTPCompression's
        /// zip-bomb guard has no counterpart to match against anyway.
        #if canImport(Darwin)
        package var decompression: Internals.Decompression = .enabled(.none)
        #else
        package var decompression: Internals.Decompression = .disabled
        #endif

        package var compression: Internals.Compression = .disabled
        package var dnsOverride: [String: String] = [:]

        /// Renamed from the old `networkFrameworkWaitForConnectivity` -- no longer a straight
        /// forward to AsyncHTTPClient's own field of that name (which only took effect on
        /// NIOTransportServices). Consumed by `Internals.NetworkPathGate` instead, via
        /// `networkPathConstraints`, uniformly across every executor. See `build()`.
        package var waitsForConnectivity: Bool?
        package var allowsCellularAccess: Bool?
        package var allowsExpensiveNetworkAccess: Bool?
        package var allowsConstrainedNetworkAccess: Bool?
        package var multipathServiceType: Internals.MultipathServiceType = .none

        package var httpVersion: Internals.HTTPVersion?
        package var enableNetworkFramework: Bool = false
        package var maximumConcurrentConnections: Int?

        // MARK: - Inits

        package init() {}

        // MARK: - Internal methods

        package func build() throws -> HTTPClient.Configuration {
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
            configuration.enableMultipath = (multipathServiceType != .none)

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

    /// `nil` when none of the four network-availability knobs were touched, so `RawTask.result()`
    /// can skip `Internals.NetworkPathGate` -- and therefore skip ever starting
    /// `Internals.NetworkPathMonitor` -- entirely for sessions that never use this API.
    package var networkPathConstraints: Internals.NetworkPathGate.Constraints? {
        guard allowsCellularAccess != nil
            || allowsExpensiveNetworkAccess != nil
            || allowsConstrainedNetworkAccess != nil
            || waitsForConnectivity != nil
        else {
            return nil
        }

        return .init(
            allowsCellularAccess: allowsCellularAccess,
            allowsExpensiveNetworkAccess: allowsExpensiveNetworkAccess,
            allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess,
            waitsForConnectivity: waitsForConnectivity
        )
    }
}
