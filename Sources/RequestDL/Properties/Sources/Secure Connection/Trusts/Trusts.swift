/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure representing trusts as a property.
 */
@RequestActor
public struct Trusts<Content: Property>: Property {

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
     Initializes a new instance of the Trusts struct.

     Example:

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

     - Parameter content: A closure that returns the content of the Trusts.
     */
    public init(@PropertyBuilder content: @RequestActor () -> Content) {
        source = .content(content())
    }

    /**
     Initializes a new instance of the Trusts struct with the specified file
     in `PEM` format.

     - Parameter file: The path to the file.
     */
    public init(_ file: String) where Content == Never {
        source = .file(file)
    }

    /**
     Initializes a new instance of the Trusts struct with the specified bytes
     in `PEM` format.

     - Parameter bytes: An array of bytes.
     */
    public init(_ bytes: [UInt8]) where Content == Never {
        source = .bytes(bytes)
    }

    /**
     Initializes a new instance of the Trusts struct with the specified file in the specified bundle
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

extension Trusts {

    private struct Node: SecureConnectionPropertyNode {

        enum Source {
            case file(String)
            case bytes([UInt8])
            case nodes([Leaf<SecureConnectionNode>])
        }

        let source: Source

        func make(_ secureConnection: inout Internals.SecureConnection) {
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

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Trusts<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .file(let file):
            return .init(Leaf(SecureConnectionNode(
                Node(source: .file(file))
            )))
        case .bytes(let bytes):
            return .init(Leaf(SecureConnectionNode(
                Node(source: .bytes(bytes))
            )))
        case .content:
            var inputs = inputs
            inputs.environment.certificateProperty = .trust

            let outputs = try await Content._makeProperty(
                property: property.content,
                inputs: inputs
            )

            return .init(Leaf(SecureConnectionNode(
                Node(source: .nodes(outputs.node
                    .search(for: SecureConnectionNode.self)
                    .filter { $0.contains(CertificateNode.self) }
                ))
            )))
        }
    }
}
