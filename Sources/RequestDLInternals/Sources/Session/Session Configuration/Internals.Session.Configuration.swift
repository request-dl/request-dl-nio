//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import NIOHTTPCompression
import Tracing

extension Internals.Session {

    package struct Configuration: Sendable {

        // MARK: - Internal properties

        package var secureConnection: Internals.SecureConnection?
        package var redirectConfiguration: Internals.RedirectConfiguration?
        package var timeout: Internals.Timeout = .init()
        package var connectionPool: HTTPClient.Configuration.ConnectionPool = .init()
        package var proxy: Internals.Proxy?
        package var ignoreUncleanSSLShutdown: Bool = false

        /// The tracer RequestDL itself uses to instrument requests -- started, ended, and populated
        /// with attributes by `RawTask.result()`, not handed to `async-http-client`.
        /// `async-http-client`'s own built-in tracing (`HTTPClient.Configuration.tracing.tracer`) is
        /// unconditionally suppressed in `build()` below: its span-start reads `ServiceContext
        /// .current` only after hopping onto a SwiftNIO `EventLoop`, which loses Swift's task-locals
        /// and makes it impossible to parent the span correctly (see `TRACER_SERVICE_CONTEXT_REPORT
        /// .md` at the repository root) -- RequestDL owns the whole span lifecycle itself instead, one
        /// layer up, entirely within the caller's own task.
        ///
        /// Defaults to a no-op tracer rather than inheriting ambient global state: RequestDL's API is
        /// declarative, so a caller that never calls `.tracer(_:)` shouldn't have their requests
        /// silently traced just because some other part of the process bootstrapped a tracer via
        /// `InstrumentationSystem` for unrelated reasons.
        ///
        /// Excluded from `Equatable` — `any Tracer` isn't `Equatable`, same reasoning as
        /// `Internals.Proxy.connectHeaders` being excluded from `Hashable`.
        package var tracer: any Tracer = NoOpTracer()

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

            // Always suppressed here, regardless of `tracer` above -- see the doc comment on that
            // property for why `async-http-client`'s own built-in tracing is never engaged.
            configuration.tracing.tracer = NoOpTracer()

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
        guard
            allowsCellularAccess != nil
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

// MARK: - Equatable

extension Internals.Session.Configuration: Equatable {

    package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.secureConnection == rhs.secureConnection
            && lhs.redirectConfiguration == rhs.redirectConfiguration
            && lhs.timeout == rhs.timeout
            && lhs.connectionPool == rhs.connectionPool
            && lhs.proxy == rhs.proxy
            && lhs.ignoreUncleanSSLShutdown == rhs.ignoreUncleanSSLShutdown
            && lhs.decompression == rhs.decompression
            && lhs.compression == rhs.compression
            && lhs.dnsOverride == rhs.dnsOverride
            && lhs.networkFrameworkWaitForConnectivity == rhs.networkFrameworkWaitForConnectivity
            && lhs.httpVersion == rhs.httpVersion
            && lhs.enableNetworkFramework == rhs.enableNetworkFramework
            && lhs.maximumConcurrentConnections == rhs.maximumConcurrentConnections
    }
}
