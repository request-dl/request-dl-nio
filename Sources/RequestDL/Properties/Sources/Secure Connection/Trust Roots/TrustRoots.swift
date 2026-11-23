//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Darwin)
import class Foundation.Bundle
#endif

/// Configure the trusted roots certificates to validate the server using TLS.
///
/// `TrustRoots` replaces the system's trusted roots, so it needs at least one certificate: one
/// that ends up with none (an empty builder, a false `if`) throws `EmptyTrustRootsError` when the
/// request is resolved, instead of silently trusting the system roots.
public struct TrustRoots<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {

        enum Source: Sendable {
            case file(String)
            case bytes([UInt8])
            case nodes([LeafNode<SecureConnectionNode>])
        }

        let source: Source

        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            secureConnection.useDefaultTrustRoots = false

            switch source {
            case .file(let file):
                secureConnection.trustRoots = .file(file)
            case .bytes(let bytes):
                secureConnection.trustRoots = .bytes(bytes)
            case .nodes(let nodes):
                var collector = secureConnection.collector()
                for node in nodes {
                    try node.passthrough(&collector)
                }

                // `TrustRoots` replaces the system roots, so a declaration that ends up with no
                // certificate (an empty builder, a false `if`, an empty `PropertyForEach`) can't
                // anchor trust on anything. Resolving it would leave `trustRoots` unset, which
                // every executor reads as "use the system store": the opposite of what was asked,
                // and silent. It fails here instead, like an empty `SPKIPinning` does.
                guard !(collector.trustRoots ?? []).isEmpty else {
                    throw Internals.EmptyTrustRootsError()
                }

                secureConnection = collector(\.trustRoots)
            }
        }
    }

    private enum Source: Sendable {
        case file(String)
        case bytes([UInt8])
        case content(Content)
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: Source

    // MARK: - Inits

    ///
    /// Instantiate using a group of ``RequestDL/Certificates`` that forms a hierarchy of trusted certificates.
    ///
    /// ```swift
    /// DataTask {
    ///    SecureConnection {
    ///        TrustRoots {
    ///            Certificate(rootPath, format: .der)
    ///            Certificate(secondPath, format: .pem)
    ///        }
    ///    }
    ///    .verification(.fullVerification)
    /// }
    /// ```
    ///
    /// - Parameter content: A closure that returns the content of ``RequestDL/Certificate``.
    ///
    public init(@PropertyBuilder content: () -> Content) {
        source = .content(content())
    }

    ///
    /// Initializes with the specified `PEM` file.
    ///
    /// - Parameter file: The path to the file.
    ///
    public init(_ file: String) where Content == Never {
        source = .file(file)
    }

    ///
    /// Initializes with the specified bytes in `PEM` format.
    ///
    /// - Parameter bytes: An array of bytes.
    ///
    public init(_ bytes: [UInt8]) where Content == Never {
        source = .bytes(bytes)
    }

    #if canImport(Darwin)
    ///
    /// Initializes with the specified `PEM` file in some bundle.
    ///
    /// - Parameters:
    ///    - file: The path to the file.
    ///    - bundle: The bundle containing the file.
    ///
    public init(
        _ file: String,
        in bundle: Bundle
    ) where Content == Never {
        self.init(Certificate.Format.pem.resolve(for: file, in: bundle))
    }
    #endif

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<TrustRoots<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .file(let file):
            return .leaf(
                SecureConnectionNode(
                    Node(source: .file(file)),
                    logger: inputs.environment.logger
                )
            )
        case .bytes(let bytes):
            return .leaf(
                SecureConnectionNode(
                    Node(source: .bytes(bytes)),
                    logger: inputs.environment.logger
                )
            )
        case .content(let content):
            var inputs = inputs
            inputs.environment.certificateProperty = .trust

            let outputs = try await Content._makeProperty(
                property: property.detach(next: content),
                inputs: inputs
            )

            return .leaf(
                SecureConnectionNode(
                    Node(
                        source: .nodes(
                            outputs.node
                                .search(for: SecureConnectionNode.self)
                                .filter { $0.contains(CertificateNode.self) }
                        )
                    ),
                    logger: inputs.environment.logger
                )
            )
        }
    }
}
