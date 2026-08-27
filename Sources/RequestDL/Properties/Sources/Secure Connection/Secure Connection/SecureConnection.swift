//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals

/// Represents a secure connection with various configuration options.
///
/// > Note: ``TrustRoots``, ``Certificates``, ``AdditionalTrustRoots``, ``PrivateKey``,
/// ``PSKIdentity``, and ``DefaultTrustRoots`` don't require nesting inside a `SecureConnection` —
/// each creates the underlying secure connection configuration on its own the first time it's
/// needed. Nest them here only when also configuring settings that live directly on
/// `SecureConnection` (`version`, `cipherSuites`, `keyLogger`, ...).
public struct SecureConnection<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {

        let secureConnection: Internals.SecureConnection
        let nodes: [LeafNode<SecureConnectionNode>]

        // Conforms to `SecureConnectionPropertyNode` (rather than mutating `Make` directly) so
        // that `_makeProperty` can wrap it in a `SecureConnectionNode`, the same leaf type this
        // node itself searches for and the same one every other secure connection property
        // (`TrustRoots`, `Certificates`, `PrivateKey`, ...) wraps itself in. Without that, a
        // `SecureConnection` nested inside another `SecureConnection` — via its own
        // `.leaf(Node(...))` collapsing everything into a private wrapper type — would be
        // invisible to the outer one's search, and every certificate/trust root/TLS setting it
        // configured would be silently dropped.
        //
        // Mirrors, synchronously, the exact sequence the top-level path already runs: replace
        // the base wholesale, then apply each found `SecureConnectionNode` on top of it via its
        // own fresh collector. `secureConnection`'s own settings (TLS version, cipher suites,
        // etc.) are not tracked field-by-field the way `trustRoots`/`certificateChain`/
        // `additionalTrustRoots` are, so nesting still replaces the whole base — only how that
        // replacement becomes reachable when nested has changed here, not what it does.
        func make(_ secureConnection: inout Internals.SecureConnection) {
            secureConnection = self.secureConnection

            for node in nodes {
                var collector = secureConnection.collector()
                node.passthrough(&collector)
                secureConnection = collector(\.self)
            }
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let content: Content

    private var secureConnection: Internals.SecureConnection

    // MARK: - Inits

    /// Initializes a secure connection with the given content.
    ///
    /// - Parameter content: A closure that provides the content of the secure connection.
    public init(
        @PropertyBuilder content: () -> Content
    ) {
        self.secureConnection = .init()
        self.content = content()
    }

    /// Initializes a secure connection with no additional content, for chaining its fluent
    /// modifiers directly — the same way `Session()` is used.
    ///
    /// ```swift
    /// DataTask {
    ///     BaseURL("apple.com")
    ///
    ///     SecureConnection()
    ///         .version(minimum: .v1_3)
    ///
    ///     TrustRoots {
    ///         Certificate(rootPath, format: .der)
    ///     }
    /// }
    /// ```
    public init() where Content == EmptyProperty {
        self.init {}
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SecureConnection<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .leaf(
            SecureConnectionNode(
                Node(
                    secureConnection: property.secureConnection,
                    nodes: outputs.node.search(for: SecureConnectionNode.self)
                ),
                logger: inputs.environment.logger
            )
        )
    }

    // MARK: - Public methods

    /// Sets the minimum TLS version for the secure connection.
    ///
    /// - Parameter minimum: The minimum TLS version to use.
    /// - Returns: A modified `SecureConnection` with the minimum TLS version set.
    public func version(minimum: TLSVersion) -> Self {
        edit { $0.secureConnection.minimumTLSVersion = minimum.build() }
    }

    /// Sets the maximum TLS version for the secure connection.
    ///
    /// - Parameter maximum: The maximum TLS version to use.
    /// - Returns: A modified `SecureConnection` with the maximum TLS version set.
    public func version(maximum: TLSVersion) -> Self {
        edit { $0.secureConnection.maximumTLSVersion = maximum.build() }
    }

    /// Sets the minimum and maximum TLS versions for the secure connection.
    ///
    /// - Parameters:
    ///   - minimum: The minimum TLS version to use.
    ///   - maximum: The maximum TLS version to use.
    /// - Returns: A modified `SecureConnection` with the minimum and maximum TLS versions set.
    public func version(minimum: TLSVersion, maximum: TLSVersion) -> Self {
        version(minimum: minimum).version(maximum: maximum)
    }

    /// Sets the TLS version range for the secure connection.
    ///
    /// - Parameter range: The range of TLS versions to use.
    /// - Returns: A modified `SecureConnection` with the TLS version range set.
    public func version(_ range: Range<TLSVersion>) -> Self {
        version(
            minimum: range.lowerBound,
            maximum: range.upperBound.downgrade
        )
    }

    /// Sets the TLS version range for the secure connection, inclusive of both ends.
    ///
    /// - Parameter range: The closed range of TLS versions to use.
    /// - Returns: A modified `SecureConnection` with the TLS version range set.
    public func version(_ range: ClosedRange<TLSVersion>) -> Self {
        version(
            minimum: range.lowerBound,
            maximum: range.upperBound
        )
    }

    /// Sets the key log object for the secure connection.
    ///
    /// - Parameter keyLogger: The `SSLKeyLogger` object.
    /// - Returns: A modified `SecureConnection` with the key logger set.
    public func keyLogger(_ keyLogger: SSLKeyLogger) -> Self {
        edit {
            $0.secureConnection.keyLogger = keyLogger
        }
    }

    /// Sets the timeout for shutting down the secure connection.
    ///
    /// - Parameter timeout: The timeout for shutting down the secure connection.
    /// - Returns: A modified `SecureConnection` with the shutdown timeout set.
    public func shutdownTimeout(_ timeout: UnitTime) -> Self {
        edit { $0.secureConnection.shutdownTimeout = timeout.build() }
    }

    /// Sets the renegotiation support for the secure connection.
    ///
    /// - Parameter renegotiationSupport: The renegotiation support setting.
    /// - Returns: A modified `SecureConnection` with the renegotiation support set.
    public func renegotiationSupport(_ renegotiationSupport: RenegotiationSupport) -> Self {
        edit { $0.secureConnection.renegotiationSupport = renegotiationSupport.build() }
    }

    /// Sets the signing signature algorithms for the secure connection.
    ///
    /// - Parameter algorithm: The signature algorithms to use for signing.
    /// - Returns: A modified `SecureConnection` with the signing signature algorithms set.
    public func signingSignatureAlgorithms(_ algorithm: SignatureAlgorithm...) -> Self {
        edit {
            $0.secureConnection.signingSignatureAlgorithms = algorithm.map {
                $0.build()
            }
        }
    }

    /// Sets the verify signature algorithms for the secure connection.
    ///
    /// - Parameter algorithm: The signature algorithms to use for verification.
    /// - Returns: A modified `SecureConnection` with the verify signature algorithms set.
    public func verifySignatureAlgorithms(_ algorithm: SignatureAlgorithm...) -> Self {
        edit {
            $0.secureConnection.verifySignatureAlgorithms = algorithm.map {
                $0.build()
            }
        }
    }

    /// Sets the certificate verification setting for the secure connection.
    ///
    /// - Parameter verification: The certificate verification setting.
    /// - Returns: A modified `SecureConnection` with the certificate verification setting set.
    public func verification(_ verification: CertificateVerification) -> Self {
        edit { $0.secureConnection.certificateVerification = verification.build() }
    }

    /// Sets the application protocols for the secure connection.
    ///
    /// - Parameter protocols: The application protocols to use.
    /// - Returns: A modified `SecureConnection` with the application protocols set.
    public func applicationProtocols(_ protocols: String...) -> Self {
        edit { $0.secureConnection.applicationProtocols = protocols }
    }

    /// Disables or enables sending the CA name list during handshake for the secure connection.
    ///
    /// - Parameter isDisabled: A boolean value indicating whether to disable or enable sending the CA name list.
    /// - Returns: A modified `SecureConnection` with the CA name list setting set.
    public func sendCANameListDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.secureConnection.sendCANameList = !isDisabled }
    }

    /// Sets the cipher suites for the secure connection using string representations.
    ///
    /// - Parameter suites: The cipher suites to use as string representations.
    /// - Returns: A modified `SecureConnection` with the cipher suites set.
    public func cipherSuites(_ suites: String...) -> Self {
        for suite in suites {
            precondition(!suite.contains(":"))
        }
        return edit { $0.secureConnection.cipherSuites = suites.joined(separator: ":") }
    }

    /// Sets the cipher suites for the secure connection using `TLSCipher` values.
    ///
    /// - Parameter suites: The cipher suites to use as `TLSCipher` values.
    /// - Returns: A modified `SecureConnection` with the cipher suites set.
    public func cipherSuites(_ suites: TLSCipher...) -> Self {
        edit {
            $0.secureConnection.cipherSuiteValues = suites.map {
                $0.build()
            }
        }
    }

    // MARK: - Internal methods

    func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }
}
