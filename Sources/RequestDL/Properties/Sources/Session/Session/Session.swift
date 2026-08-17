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
    /// - Parameter enabled: The flag to enable the Network framework
    /// - Returns: A modified property with Network framework enabled.
    ///
    public func enableNetworkFramework(_ enabled: Bool = true) -> some Property {
        edit { $0.enableNetworkFramework = enabled }
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
