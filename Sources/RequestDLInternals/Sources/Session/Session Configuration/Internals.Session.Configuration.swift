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
        /// and makes it impossible to parent the span correctly -- RequestDL owns the whole span
        /// lifecycle itself instead, one layer up, entirely within the caller's own task.
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

            if case .bearer = proxy.authorization {
                reasons.append(.proxyBearerAuthorizationUnderURLSession)
            }
        }

        if case .disabled = decompression {
            reasons.append(.decompressionDisabledUnderURLSession)
        }

        return reasons
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
            && lhs.waitsForConnectivity == rhs.waitsForConnectivity
            && lhs.allowsCellularAccess == rhs.allowsCellularAccess
            && lhs.allowsExpensiveNetworkAccess == rhs.allowsExpensiveNetworkAccess
            && lhs.allowsConstrainedNetworkAccess == rhs.allowsConstrainedNetworkAccess
            && lhs.multipathServiceType == rhs.multipathServiceType
            && lhs.httpVersion == rhs.httpVersion
            && lhs.enableNetworkFramework == rhs.enableNetworkFramework
            && lhs.maximumConcurrentConnections == rhs.maximumConcurrentConnections
            // `preferredExecutor` is a soft hint, so two configurations differing only there could
            // arguably still share a pooled client -- but `requiredExecutor` is a hard pin, and
            // `Internals.ClientManager` uses this `==` as its pooled-client cache key
            // (`item.sessionConfiguration == sessionConfiguration`). Omitting either would let a
            // request pinned to one executor silently reuse a pooled client resolved for another,
            // defeating the pin. Both are included together for that reason, not just the one that
            // strictly has to be.
            && lhs.preferredExecutor == rhs.preferredExecutor
            && lhs.requiredExecutor == rhs.requiredExecutor
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
    ///
    /// - Important: `requiredExecutor`, when set, is returned unconditionally, without
    /// re-checking compatibility here -- that check already happened, and already threw if it
    /// failed, in `requireExecutor(_:)` (called separately, before this, by `RawTask.result()`).
    /// A caller that reaches this method with `requiredExecutor` set and never called
    /// `requireExecutor(_:)` first bypasses that guarantee -- same contract `Internals.ClientManager
    /// .resolvedClient(provider:sessionConfiguration:)`'s own callers already have to honor.
    ///
    /// - Important: `enableNetworkFramework(true)` (`Session.enableNetworkFramework(_:)`, already
    /// public/released API predating `preferredExecutor`) is treated as an implicit
    /// `preferredExecutor(.nioTransportServices)` when nothing else already set one. Needed
    /// because this method's own NIOTransportServices-vs-plain-NIO answer now actually drives a
    /// real request (rather than only `enableNetworkFramework`, read independently by
    /// `Internals.ClientManager.client(provider:sessionConfiguration:)`): without the implicit
    /// preference, `.urlSession`'s default first-priority position would otherwise silently take
    /// over for anyone calling only `enableNetworkFramework(true)` -- a transport switch neither
    /// this flag's existing callers nor its own doc comment ever signed up for. An explicit
    /// `preferredExecutor` (any case, including `.urlSession`) still wins over this implicit one.
    package func resolveExecutor() -> Internals.Executor {
        if let requiredExecutor {
            return requiredExecutor
        }

        #if canImport(Darwin)
        let isURLSessionCompatible = urlSessionIncompatibilityReasons().isEmpty
        let isNetworkFrameworkCompatible = secureConnection?.networkFrameworkIncompatibilityReasons().isEmpty ?? true

        let effectivePreferredExecutor = preferredExecutor ?? (enableNetworkFramework ? .nioTransportServices : nil)

        // `effectivePreferredExecutor` only ever reorders among the candidates the two checks
        // above already say are compatible -- it is never consulted on its own, and never
        // returned without the matching compatibility check passing first. `.nio` needs no such
        // check: it is the universal fallback (`requireExecutor(_:)` never produces reasons for
        // it either).
        switch effectivePreferredExecutor {
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
    /// `Internals.Client`.
    ///
    /// Ephemeral: no disk-backed cache or cookie storage to leak across the cache entries
    /// `Internals.ClientManager` pools and later shuts down. Cookies are additionally disabled
    /// unconditionally in `Internals.URLSessionClient.init` itself regardless of what this builds.
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

        // `.ephemeral` only means "don't persist to disk" -- it still ships a real, if small,
        // in-memory `URLCache` and defaults `requestCachePolicy` to `.useProtocolCachePolicy`,
        // which independently interprets standard HTTP caching semantics (including request
        // directives like `Cache-Control: only-if-cached`) against that cache before a request
        // ever reaches the network. `Internals.CacheControl`/`DataCache` already own caching
        // entirely on RequestDL's side; a second, invisible cache layer underneath URLSession
        // does nothing useful and actively conflicts with it -- an `only-if-cached` request
        // RequestDL's own logic correctly decided should hit the network (nothing configured
        // locally to serve it from) would otherwise fail outright with `NSURLErrorDomain` -2000
        // ("can't load from network"), since URLSession's own cache has nothing either and
        // `.useProtocolCachePolicy` refuses to fall through past that. Ignoring URLSession's
        // cache unconditionally routes every request to the network, where RequestDL's own
        // cache/strategy logic already decided whether it should run at all.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        if let read = timeout.read {
            configuration.timeoutIntervalForRequest = TimeInterval(read) / 1_000_000_000
        }

        return configuration
    }
}

#endif
