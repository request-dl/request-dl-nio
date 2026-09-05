//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals
import Tracing

/// The Session object is used to set various properties related to the request context.
///
/// By using this object, we can centralize the creation of a single type of session to be used
/// in all requests.
///
/// ```swift
/// struct MyAppConfiguration: Property {
///
///     var body: some Property {
///         Session()
///             .waitsForConnectivity(true)
///
///         Timeout(10)
///     }
/// }
/// ```
public struct Session: Property {

    private struct Node: PropertyNode {

        let configuration: (@Sendable (inout Internals.Session.Configuration) -> Void)?
        let provider: SessionProvider

        func make(_ make: inout Make) async throws {
            configuration?(&make.sessionConfiguration)
            make.provider = provider
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    private(set) var configuration: (@Sendable (inout Internals.Session.Configuration) -> Void)?
    let provider: SessionProvider

    // MARK: - Inits

    /// Initializes a new Session object.
    public init() {
        provider = .shared
    }

    ///
    /// Initializes a new Session object with a custom identifier and number of threads.
    ///
    /// - Parameters:
    ///    - identifier: A custom identifier for the session.
    ///    - numberOfThreads: The number of threads to use for the session. Defaults to 1.
    ///
    public init(
        _ identifier: String,
        numberOfThreads: Int = 1
    ) {
        provider = .identified(identifier, numberOfThreads: numberOfThreads)
    }

    public init(_ customLoopGroup: NIOCore.EventLoopGroup) {
        provider = .custom(customLoopGroup)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Session>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                configuration: property.configuration,
                provider: property.provider
            )
        )
    }

    // MARK: - Public methods

    ///
    /// Set whether the session should wait for connectivity before making a request.
    ///
    /// Checked once, right before the request is dispatched, against the device's current
    /// network path — the same way `URLSession`'s own `waitsForConnectivity` only covers a
    /// task's initial connection phase, never a network change mid-transfer. Effective across
    /// every executor (previously this only had any effect when Network framework backed the
    /// connection).
    ///
    /// - Parameter flag: `true` to wait for connectivity or `false` to not wait for it.
    /// - Returns: The modified `Session` instance with the waiting for connectivity flag configured.
    ///
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        edit { $0.waitsForConnectivity = flag }
    }

    ///
    /// Set whether the session may send requests over a cellular network path.
    ///
    /// Enforced with a pre-flight check against the device's current network path, mirroring
    /// `URLSessionConfiguration.allowsCellularAccess` — see ``NetworkAvailabilityError``.
    ///
    /// - Parameter flag: `true` to allow cellular access, `false` to require a non-cellular path.
    /// - Returns: The modified `Session` instance with the cellular-access flag configured.
    ///
    public func allowsCellularAccess(_ flag: Bool) -> Self {
        edit { $0.allowsCellularAccess = flag }
    }

    ///
    /// Set whether the session may send requests over an expensive network path (for example, a
    /// personal hotspot or a metered connection).
    ///
    /// Enforced with a pre-flight check against the device's current network path, mirroring
    /// `URLSessionConfiguration.allowsExpensiveNetworkAccess` — see ``NetworkAvailabilityError``.
    ///
    /// - Parameter flag: `true` to allow expensive access, `false` to require a non-expensive path.
    /// - Returns: The modified `Session` instance with the expensive-access flag configured.
    ///
    public func allowsExpensiveNetworkAccess(_ flag: Bool) -> Self {
        edit { $0.allowsExpensiveNetworkAccess = flag }
    }

    ///
    /// Set whether the session may send requests over a constrained network path (for example,
    /// when the user has enabled Low Data Mode).
    ///
    /// Enforced with a pre-flight check against the device's current network path, mirroring
    /// `URLSessionConfiguration.allowsConstrainedNetworkAccess` — see ``NetworkAvailabilityError``.
    ///
    /// - Parameter flag: `true` to allow constrained access, `false` to require an unconstrained path.
    /// - Returns: The modified `Session` instance with the constrained-access flag configured.
    ///
    public func allowsConstrainedNetworkAccess(_ flag: Bool) -> Self {
        edit { $0.allowsConstrainedNetworkAccess = flag }
    }

    ///
    /// Configures multipath TCP for the session, mirroring `URLSessionConfiguration.multipathServiceType`.
    ///
    /// - Parameter type: The multipath service type to use.
    /// - Returns: The modified `Session` instance with multipath configured.
    ///
    public func multipathServiceType(_ type: MultipathServiceType) -> Self {
        edit { $0.multipathServiceType = type.build() }
    }

    ///
    /// Enable the usage of Network framework on Apple Platforms when compatible.
    ///
    /// Currently AsyncHTTPClient doesn't provide full compatibility to Apple's Network Framework. The main issue is when using mTLS
    /// or specific secure connection settings -- including ``SPKIPinning``, which Network framework's bridge into
    /// `sec_protocol_options` never consults. When the session's ``SecureConnection`` carries any such setting, this flag
    /// is silently ignored and the session falls back to plain SwiftNIO instead of failing or dropping the incompatible
    /// setting: whichever secure-connection settings were configured still apply in full, just over a different transport.
    ///
    /// - Note: Deprecated in favor of ``preferredExecutor(_:)`` -- specifically
    /// `.preferredExecutor(.nioTransportServices)`, which is wired into the same live decision
    /// this flag drives. `enableNetworkFramework(true)` keeps working exactly as before: it's
    /// treated as an *implicit* `preferredExecutor(.nioTransportServices)` whenever nothing else
    /// already set a preference, so this deprecation doesn't silently change which transport an
    /// existing caller gets. An explicit `preferredExecutor` (any case) still overrides that
    /// implicit one. New code should call `preferredExecutor(.nioTransportServices)` directly
    /// rather than lean on this shim.
    ///
    /// - Parameter enabled: The flag to enable the Network framework
    /// - Returns: A modified property with Network framework enabled.
    ///
    @available(
        *,
        deprecated,
        message:
            "Use .preferredExecutor(.nioTransportServices) instead. enableNetworkFramework(true) already resolves to exactly that internally, so existing behavior is unchanged -- this now exists only for source compatibility."
    )
    public func enableNetworkFramework(_ enabled: Bool = true) -> Self {
        edit { $0.enableNetworkFramework = enabled }
    }

    ///
    /// Prefers `executor` for this session's requests, among whichever executors the rest of its
    /// configuration is already compatible with.
    ///
    /// This is a tiebreaker, not an override: it never forces an executor onto a configuration
    /// that can't actually run on it. For example, preferring ``Session/Executor/nioTransportServices``
    /// on a session that also sets `PSKIdentityResolver` (unsupported under Network.framework)
    /// has no effect — that field already rules `.nioTransportServices` out on its own, so
    /// resolution falls through to whatever is next in line. If you need a guarantee instead of a
    /// hint — so an incompatible configuration fails loudly instead of silently landing somewhere
    /// else — use ``requiredExecutor(_:)``.
    ///
    /// - Parameter executor: The executor to prefer when this session's configuration supports it.
    /// - Returns: The modified `Session` instance with the executor preference configured.
    ///
    public func preferredExecutor(_ executor: Session.Executor) -> Self {
        edit { $0.preferredExecutor = executor.build() }
    }

    ///
    /// Pins this session to `executor`, failing the request rather than silently falling back
    /// when the rest of its configuration can't actually run on it.
    ///
    /// Unlike ``preferredExecutor(_:)``, this is a guarantee: if any configured field is
    /// unsupported under `executor` — a client certificate under `.nioTransportServices`, a
    /// bearer-token proxy authorization under `.urlSession`, and so on — the request throws
    /// ``ExecutorRequirementError``
    /// instead of quietly running on a different executor than the one you pinned. Useful for
    /// debugging, benchmarking a specific transport, or a deployment target where only one
    /// executor is actually viable and a silent fallback would hide a real misconfiguration.
    ///
    /// Pinning to ``Session/Executor/urlSession`` with a client certificate configured
    /// (``Certificate``/``PrivateKey`` on ``SecureConnection``) has one further requirement
    /// ``ExecutorRequirementError`` can't check ahead of time: building that certificate into a
    /// `URLSession`-presentable identity is a Keychain round-trip that needs the Keychain Sharing
    /// capability, a one-time Xcode project setting. A request missing it throws
    /// ``ClientIdentityError`` instead — see <doc:Using-a-Client-Certificate-with-URLSession>
    /// for the full walkthrough. This also applies without pinning anything, since `.urlSession`
    /// is already ``preferredExecutor(_:)``'s own default choice on Darwin whenever the rest of
    /// the configuration supports it.
    ///
    /// ```swift
    /// struct MyRequest: Property {
    ///     var body: some Property {
    ///         BaseURL("api.example.com")
    ///         Session().requiredExecutor(.urlSession)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter executor: The executor this session's configuration must be compatible with.
    /// - Returns: The modified `Session` instance with the executor requirement configured.
    ///
    public func requiredExecutor(_ executor: Session.Executor) -> Self {
        edit { $0.requiredExecutor = executor.build() }
    }

    ///
    /// Configures the maximum number of connections per host for the session.
    ///
    /// - Parameter maximum: The maximum number of connections per host.
    /// - Returns: The modified `Session` instance with the maximum connections per host configured.
    ///
    public func maximumConnectionsPerHost(_ maximum: Int) -> Self {
        edit { $0.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = maximum }
    }

    ///
    /// Caps how many requests made through this session may be in flight at once, across every
    /// host, from the moment a request is asked to execute until it completes.
    ///
    /// Unlike ``maximumConnectionsPerHost(_:)``, which is a per-host soft limit that AsyncHTTPClient
    /// may exceed, this is an exact, session-wide cap: once it is reached, further requests wait
    /// in line for a slot to free up rather than opening another connection.
    ///
    /// - Parameter maximum: The maximum number of requests this session may have in flight at once.
    /// - Returns: The modified `Session` instance with the concurrency limit configured.
    ///
    public func maximumConcurrentConnections(_ maximum: Int) -> Self {
        edit { $0.maximumConcurrentConnections = maximum }
    }

    ///
    /// Disables redirect for the session.
    ///
    /// - Returns: The modified `Session` instance with redirect disabled.
    ///
    public func disableRedirect() -> Self {
        edit { $0.redirectConfiguration = .disallow }
    }

    ///
    /// Enables redirect follow for the session.
    ///
    /// - Parameters:
    /// - max: The maximum number of redirects to follow.
    /// - allowCycles: Whether to allow redirect cycles or not.
    /// - Returns: The modified `Session` instance with redirect follow enabled.
    ///
    public func enableRedirectFollow(max: Int, allowCycles: Bool) -> Self {
        edit { $0.redirectConfiguration = .follow(max: max, allowCycles: allowCycles) }
    }

    ///
    /// Hands every redirect-eligible response to `strategy`, which decides whether -- and how --
    /// to follow it, instead of the fixed count/cycle limit ``enableRedirectFollow(max:allowCycles:)``
    /// applies. See ``RedirectStrategy``.
    ///
    /// - Parameter strategy: The strategy that decides each redirect.
    /// - Returns: The modified `Session` instance with the redirect strategy configured.
    ///
    public func redirectStrategy(_ strategy: some RedirectStrategy) -> Self {
        edit { $0.redirectConfiguration = .strategy(InternalsRedirectStrategyAdapter(strategy: strategy)) }
    }

    ///
    /// Convenience over ``redirectStrategy(_:)`` for a policy that doesn't need its own type:
    /// every redirect-eligible response is handed to `handler`, which decides whether -- and how
    /// -- to follow it. See ``RedirectContext`` for what `handler` receives.
    ///
    /// - Parameter handler: The closure that decides each redirect.
    /// - Returns: The modified `Session` instance with the redirect strategy configured.
    ///
    public func onRedirect(
        _ handler: @escaping @Sendable (RedirectContext) throws -> RedirectDecision
    ) -> Self {
        redirectStrategy(ClosureRedirectStrategy(handler: handler))
    }

    ///
    /// Disables decompression for the session.
    ///
    /// - Returns: The modified `Session` instance with decompression disabled.
    ///
    public func disableDecompression() -> Self {
        edit { $0.decompression = .disabled }
    }

    ///
    /// Configures the decompression limit for the session.
    ///
    /// - Parameter decompressionLimit: The decompression limit to set.
    /// - Returns: The modified `Session` instance with the decompression limit configured.
    ///
    public func decompressionLimit(_ decompressionLimit: DecompressionLimit) -> Self {
        edit { $0.decompression = .enabled(decompressionLimit.build()) }
    }

    ///
    /// Compresses the outgoing request body before it's sent, setting the `Content-Encoding`
    /// header accordingly.
    ///
    /// This is independent of which `Payload` source produced the body (`Data`/`JSON`/`String`/
    /// `File`/`Form`) and of which ``Session/Executor`` the request resolves to -- the body is
    /// compressed once, up front, rather than on the wire, so `.urlSession`/`.nioTransportServices`/
    /// `.nio` and every negotiated HTTP version all see the same already-compressed bytes.
    ///
    /// Compression is only worth its CPU cost for bodies that are both sizable and not already
    /// compressed (a large JSON payload, say, but not an image) -- use `shouldCompressBodyData`
    /// to gate it on the body's byte count, the same threshold Alamofire's own
    /// `DeflateRequestCompressor.shouldCompressBodyData` recommends. Left `nil`, every request
    /// with a body is compressed whenever `compression` is enabled, regardless of size.
    ///
    /// - Parameters:
    ///   - algorithm: The algorithm used to compress the request body.
    ///   - behavior: What to do if the request already carries a `Content-Encoding` header.
    ///   Defaults to ``DuplicateHeaderBehavior/error``.
    ///   - shouldCompressBodyData: Given the outgoing body's byte count, decides whether to
    ///   compress it. Defaults to `nil`, which always compresses.
    /// - Returns: The modified `Session` instance with request-body compression configured.
    ///
    public func compression(
        _ algorithm: CompressionAlgorithm,
        onDuplicateHeader behavior: DuplicateHeaderBehavior = .error,
        shouldCompressBodyData: (@Sendable (Int) -> Bool)? = nil
    ) -> Self {
        edit {
            $0.compression = .enabled(algorithm.build())
            $0.compressionDuplicateHeaderBehavior = behavior.build()
            $0.shouldCompressBodyData = shouldCompressBodyData
        }
    }

    ///
    /// Sets the tracer used to record distributed tracing spans for requests made through this
    /// session.
    ///
    /// When not set, no tracing is performed — the session uses a no-op tracer, regardless of
    /// whether some other part of the process has globally bootstrapped one via
    /// `InstrumentationSystem.bootstrap(_:)`. Tracing is opt-in per session, not ambient.
    ///
    /// - Parameter tracer: The tracer to use for this session.
    /// - Returns: The modified `Session` instance with the tracer configured.
    ///
    public func tracer(_ tracer: any Tracer) -> Self {
        edit { $0.tracer = tracer }
    }

    // MARK: - Private properties

    private func edit(
        _ edit: @Sendable @escaping (inout Internals.Session.Configuration) -> Void
    ) -> Self {
        var mutableSelf = self
        mutableSelf.configuration = {
            configuration?(&$0)
            edit(&$0)
        }
        return mutableSelf
    }
}
