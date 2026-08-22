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
        package var networkFrameworkWaitForConnectivity: Bool?
        package var httpVersion: Internals.HTTPVersion?
        package var enableNetworkFramework: Bool = false
        package var maximumConcurrentConnections: Int?

        /// Soft hint: reorders `resolveExecutor()`'s pick among the executors this configuration
        /// is already compatible with -- never forces one it isn't. `nil` leaves the default
        /// priority order (`.urlSession` › `.nioTransportServices` › `.nio`) untouched. See
        /// `Session.preferredExecutor(_:)`.
        package var preferredExecutor: Internals.Executor?

        /// Hard pin: `requireExecutor(_:)` throws `IncompatibleExecutorConfigurationError` rather
        /// than falling back when this is set and the configuration can't actually run on it.
        /// `nil` means no pin -- resolution is free to fall back. See
        /// `Session.requiredExecutor(_:)`.
        package var requiredExecutor: Internals.Executor?

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

    /// The bucket-D fields that keep a configuration off `.urlSession` regardless of what
    /// `secureConnection` allows -- these are AsyncHTTPClient/HTTP-layer concerns orthogonal to
    /// which TLS transport is underneath, so they're checked here rather than on `SecureConnection`.
    package func urlSessionIncompatibilityReasons() -> [Internals.ExecutorIncompatibilityReason] {
        var reasons = secureConnection?.urlSessionIncompatibilityReasons() ?? []

        if !dnsOverride.isEmpty {
            reasons.append(.dnsOverrideUnderURLSession)
        }

        if httpVersion == .http1Only {
            reasons.append(.http1OnlyUnderURLSession)
        }

        if let proxy {
            if !proxy.connectHeaders.isEmpty {
                reasons.append(.proxyConnectHeadersUnderURLSession)
            }

            if proxy.connectionProtocol == .socks {
                reasons.append(.proxySOCKSUnderURLSession)
            }

            if case .bearer = proxy.authorization {
                reasons.append(.proxyBearerAuthorizationUnderURLSession)
            }
        }

        if case .disabled = decompression {
            reasons.append(.decompressionDisabledUnderURLSession)
        }

        return reasons
    }
}

extension Internals.Session.Configuration {

    /// Picks the best executor this configuration actually supports, in priority order.
    ///
    /// URLSession is tried first on Apple platforms -- best OS integration (background transfers,
    /// ATS, HTTP/3 maturity) -- then NIOTransportServices, then plain NIO as the universal
    /// fallback. `.urlSession` and `.nioTransportServices` are independent capability checks, not
    /// a hierarchy: a field can be reachable on one and not the other (see
    /// `urlSessionIncompatibilityReasons()`/`SecureConnection.networkFrameworkIncompatibilityReasons()`).
    /// This is a default ordering, not a fixed law -- `preferredExecutor`/`requiredExecutor`
    /// (public API) let a caller override it.
    package func resolveExecutor() -> Internals.Executor {
        #if canImport(Darwin)
        let isURLSessionCompatible = urlSessionIncompatibilityReasons().isEmpty
        let isNetworkFrameworkCompatible = secureConnection?.networkFrameworkIncompatibilityReasons().isEmpty ?? true

        // `preferredExecutor` only ever reorders among the candidates the two checks above
        // already say are compatible -- it is never consulted on its own, and never returned
        // without the matching compatibility check passing first. `.nio` needs no such check: it
        // is the universal fallback (`requireExecutor(_:)` never produces reasons for it either).
        switch preferredExecutor {
        case .urlSession where isURLSessionCompatible:
            return .urlSession
        case .nioTransportServices where isNetworkFrameworkCompatible:
            return .nioTransportServices
        case .nio:
            return .nio
        case .urlSession, .nioTransportServices, nil:
            break
        }

        if isURLSessionCompatible {
            return .urlSession
        }
        if isNetworkFrameworkCompatible {
            return .nioTransportServices
        }
        #endif
        return .nio
    }

    /// Hard-pins execution to `executor`, throwing rather than silently falling back when this
    /// configuration can't actually run on it.
    ///
    /// This is the direct fix for the bug class #289 closed: NIOTransportServices used to
    /// silently drop settings it couldn't carry over instead of failing loudly. A caller pinning
    /// an executor explicitly is asking for a guarantee, not a best-effort -- ignoring what it
    /// can't do here would just move that same silent-degradation bug to a new call site.
    package func requireExecutor(_ executor: Internals.Executor) throws {
        let reasons: [Internals.ExecutorIncompatibilityReason]

        switch executor {
        case .urlSession:
            reasons = urlSessionIncompatibilityReasons()
        case .nioTransportServices:
            reasons = secureConnection?.networkFrameworkIncompatibilityReasons() ?? []
        case .nio:
            reasons = []
        }

        guard reasons.isEmpty else {
            throw Internals.IncompatibleExecutorConfigurationError(
                requiredExecutor: executor,
                reasons: reasons
            )
        }
    }
}

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.Session.Configuration {

    /// `URLSession` counterpart to `build() -> HTTPClient.Configuration` -- built fresh per
    /// `Internals.URLSessionClient` instance, mirroring how `build()` is also called once per
    /// `Internals.Client`. Phase 6 of `URLSESSION_TASK.md`.
    ///
    /// Ephemeral: no disk-backed cache or cookie storage to leak across the cache entries
    /// `Internals.ClientManager` pools and later shuts down. Cookies are additionally disabled
    /// unconditionally in `Internals.URLSessionClient.init` itself (Phase 5d) regardless of what
    /// this builds.
    ///
    /// Only `timeout.read` maps onto `timeoutIntervalForRequest` -- `URLSessionConfiguration` has
    /// no distinct connect-phase timeout to receive `timeout.connect`. Every other field this
    /// configuration could carry that has no `URLSessionConfiguration` counterpart (`connectionPool`,
    /// `ignoreUncleanSSLShutdown`, `networkFrameworkWaitForConnectivity`, `compression`) is either
    /// NIO/NIOTS-specific with nothing to translate to, or -- for the fields that matter, like
    /// `dnsOverride`/`httpVersion == .http1Only`/`proxy.connectHeaders`/`.socks`/`.bearer`/
    /// `decompression == .disabled` -- already excluded from resolving to `.urlSession` at all by
    /// `urlSessionIncompatibilityReasons()`, so there is nothing left for a compatible
    /// configuration to lose in translation.
    func buildURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral

        if let read = timeout.read {
            configuration.timeoutIntervalForRequest = TimeInterval(read) / 1_000_000_000
        }

        return configuration
    }
}

#endif
