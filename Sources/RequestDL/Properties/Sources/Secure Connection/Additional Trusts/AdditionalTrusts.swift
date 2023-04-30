/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure representing additional trusts as a property.
 */
@RequestActor
public struct AdditionalTrusts<Content: Property>: Property {

    enum Source {
        case file(String)
        case bytes([UInt8])
        case content(Content)
    }

    let source: Source

    var content: Content {
        guard case .content(let content) = source else {
            Internals.Log.failure(
                .unexpectedCertificateSource(source)
            )
        }

        return content
    }

    /**
     Initializes a new instance of the AdditionalTrusts struct.

     Example:

     ```swift
     DataTask {
        SecureConnection {
            AdditionalTrust {
                Certificate(rootPath, format: .der)
                Certificate(secondPath, format: .pem)
            }
        }
        .verification(.fullVerification)
     }
     ```

     - Parameter content: A closure that returns the content of the AdditionalTrusts.
     */
    public init(@PropertyBuilder content: @RequestActor () -> Content) {
        source = .content(content())
    }

    /**
     Initializes a new instance of the AdditionalTrusts struct with the specified file
     in `PEM` format.

     - Parameter file: The path to the file.
     */
    public init(_ file: String) where Content == Never {
        source = .file(file)
    }

    /**
     Initializes a new instance of the AdditionalTrusts struct with the specified bytes
     in `PEM` format.

     - Parameter bytes: An array of bytes.
     */
    public init(_ bytes: [UInt8]) where Content == Never {
        source = .bytes(bytes)
    }

    /**
     Initializes a new instance of the AdditionalTrusts struct with the specified file in the specified bundle
     in `PEM` format.

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

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension AdditionalTrusts {

    private struct Node: SecureConnectionPropertyNode {

        enum Source {
            case file(String)
            case bytes([UInt8])
            case nodes([LeafNode<SecureConnectionNode>])
        }

        let source: Source

        func make(_ secureConnection: inout Internals.SecureConnection) {
            switch source {
            case .file(let file):
                var additionalTrustRoots = secureConnection.additionalTrustRoots ?? []
                additionalTrustRoots.append(.file(file))
                secureConnection.additionalTrustRoots = additionalTrustRoots
            case .bytes(let bytes):
                var additionalTrustRoots = secureConnection.additionalTrustRoots ?? []
                additionalTrustRoots.append(.bytes(bytes))
                secureConnection.additionalTrustRoots = additionalTrustRoots
            case .nodes(let nodes):
                var collector = secureConnection.collector()
                for node in nodes {
                    node.passthrough(&collector)
                }
                secureConnection = collector(\.additionalTrustRoots)
            }
        }
    }

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<AdditionalTrusts<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .file(let file):
            return .leaf(SecureConnectionNode(
                Node(source: .file(file))
            ))
        case .bytes(let bytes):
            return .leaf(SecureConnectionNode(
                Node(source: .bytes(bytes))
            ))
        case .content:
            var inputs = inputs
            inputs.environment.certificateProperty = .additionalTrust

            let outputs = try await Content._makeProperty(
                property: property.content,
                inputs: inputs
            )

            return .leaf(SecureConnectionNode(
                Node(source: .nodes(outputs.node
                    .search(for: SecureConnectionNode.self)
                    .filter { $0.contains(CertificateNode.self) }
                ))
            ))
        }
    }
}
