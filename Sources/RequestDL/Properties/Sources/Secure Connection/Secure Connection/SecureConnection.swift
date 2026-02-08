/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

/// Represents a secure connection with various configuration options.
public struct SecureConnection<Content: Property>: Property {

    private struct Node: PropertyNode {

        let secureConnection: Internals.SecureConnection
        let nodes: [LeafNode<SecureConnectionNode>]

        func make(_ make: inout Make) async throws {
            make.sessionConfiguration.secureConnection = secureConnection

            for node in nodes {
                try await node.make(&make)
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

        return .leaf(Node(
            secureConnection: property.secureConnection,
            nodes: outputs.node.search(for: SecureConnectionNode.self)
        ))
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
    /// - Parameter closure: The `SSLKeyLogger` object.
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
        suites.forEach { precondition(!$0.contains(":")) }
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
