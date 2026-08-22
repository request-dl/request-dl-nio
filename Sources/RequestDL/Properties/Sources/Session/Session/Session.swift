//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals

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
    /// - Parameter flag: `true` to wait for connectivity or `false` to not wait for it.
    /// - Returns: The modified `Session` instance with the waiting for connectivity flag configured.
    ///
    public func waitsForConnectivity(_ flag: Bool) -> Self {
        edit { $0.networkFrameworkWaitForConnectivity = flag }
    }

    ///
    /// Enable the usage of Network framework on Apple Platforms when compatible.
    ///
    /// Currently AsyncHTTPClient doesn't provide full compatibility to Apple's Network Framework. The main issue is when using mTLS
    /// or specific secure connection settings.
    ///
    /// - Note: Not yet deprecated in favor of ``preferredExecutor(_:)``, even though both concern
    /// Network.framework (``Session/Executor/nioTransportServices``): this is the flag that
    /// actually opts a session into it today, while `.preferredExecutor(.nioTransportServices)`
    /// is not yet wired into that same decision. The two will be unified in a later release, at
    /// which point this may become the deprecated one.
    ///
    /// - Parameter enabled: The flag to enable the Network framework
    /// - Returns: A modified property with Network framework enabled.
    ///
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
    /// unsupported under `executor` — a client certificate under `.nioTransportServices`, a SOCKS
    /// proxy under `.urlSession`, and so on — the request throws ``ExecutorRequirementError``
    /// instead of quietly running on a different executor than the one you pinned. Useful for
    /// debugging, benchmarking a specific transport, or a deployment target where only one
    /// executor is actually viable and a silent fallback would hide a real misconfiguration.
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
    /// Compresses the outgoing request body before it's sent over the wire, setting the
    /// `Content-Encoding` header accordingly.
    ///
    /// This is independent of which `Payload` source produced the body (`Data`/`JSON`/`String`/
    /// `File`/`Form`) and only applies to connections negotiated as HTTP/1.1.
    ///
    /// - Parameter algorithm: The algorithm used to compress the request body.
    /// - Returns: The modified `Session` instance with request-body compression configured.
    ///
    public func compression(_ algorithm: CompressionAlgorithm) -> Self {
        edit { $0.compression = .enabled(algorithm.build()) }
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
