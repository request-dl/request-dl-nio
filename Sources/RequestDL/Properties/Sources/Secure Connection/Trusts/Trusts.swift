/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Configure the trusted certificates to validate the server using TLS.
public struct Trusts<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {

        enum Source: Sendable {
            case file(String)
            case bytes([UInt8])
            case nodes([LeafNode<SecureConnectionNode>])
        }

        let source: Source

        func make(_ secureConnection: inout Internals.SecureConnection) {
            secureConnection.useDefaultTrustRoots = false

            switch source {
            case .file(let file):
                secureConnection.trustRoots = .file(file)
            case .bytes(let bytes):
                secureConnection.trustRoots = .bytes(bytes)
            case .nodes(let nodes):
                var collector = secureConnection.collector()
                for node in nodes {
                    node.passthrough(&collector)
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

    /**
     Instantiate using a group of ``RequestDL/Certificates`` that forms a hierarchy of trusted certificates.

     ```swift
     DataTask {
        SecureConnection {
            Trusts {
                Certificate(rootPath, format: .der)
                Certificate(secondPath, format: .pem)
            }
        }
        .verification(.fullVerification)
     }
     ```

     - Parameter content: A closure that returns the content of ``RequestDL/Certificate``.
     */
    public init(@PropertyBuilder content: () -> Content) {
        source = .content(content())
    }

    /**
     Initializes with the specified `PEM` file.

     - Parameter file: The path to the file.
     */
    public init(_ file: String) where Content == Never {
        source = .file(file)
    }

    /**
     Initializes with the specified bytes in `PEM` format.

     - Parameter bytes: An array of bytes.
     */
    public init(_ bytes: [UInt8]) where Content == Never {
        source = .bytes(bytes)
    }

    /**
     Initializes with the specified `PEM` file in some bundle.

     - Parameters:
        - file: The path to the file.
        - bundle: The bundle containing the file.
     */
    public init(
        _ file: String,
        in bundle: Bundle
    ) where Content == Never {
        self.init(Certificate.Format.pem.resolve(for: file, in: bundle))
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Trusts<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .file(let file):
            return .leaf(SecureConnectionNode(
                Node(source: .file(file)),
                logger: inputs.environment.logger
            ))
        case .bytes(let bytes):
            return .leaf(SecureConnectionNode(
                Node(source: .bytes(bytes)),
                logger: inputs.environment.logger
            ))
        case .content(let content):
            var inputs = inputs
            inputs.environment.certificateProperty = .trust

            let outputs = try await Content._makeProperty(
                property: property.detach(next: content),
                inputs: inputs
            )

            return .leaf(SecureConnectionNode(
                Node(source: .nodes(outputs.node
                    .search(for: SecureConnectionNode.self)
                    .filter { $0.contains(CertificateNode.self) }
                )),
                logger: inputs.environment.logger
            ))
        }
    }
}
