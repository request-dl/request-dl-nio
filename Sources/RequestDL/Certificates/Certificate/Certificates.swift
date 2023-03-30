/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Certificates<Content: Property>: Property {

    enum Source {
        case file(String)
        case bytes([UInt8])
        case content(Content)
    }

    let source: Source

    var content: Content {
        guard case .content(let content) = source else {
            fatalError()
        }

        return content
    }

    public init(@PropertyBuilder content: () -> Content) {
        source = .content(content())
    }

    public init(_ file: String) where Content == Never {
        source = .file(file)
    }

    public init(_ bytes: [UInt8]) where Content == Never {
        source = .bytes(bytes)
    }

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

extension Certificates {

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
                secureConnection.certificateChain = .file(file)
            case .bytes(let bytes):
                secureConnection.certificateChain = .bytes(bytes)
            case .nodes(let nodes):
                var collector = secureConnection.collector()
                for node in nodes {
                    node.passthrough(&collector)
                }
                secureConnection = collector(\.certificateChain)
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Certificates<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        switch property.source {
        case .file(let file):
            _ = inputs[self]

            return .init(Leaf(SecureConnectionNode(
                Node(source: .file(file))
            )))
        case .bytes(let bytes):
            _ = inputs[self]

            return .init(Leaf(SecureConnectionNode(
                Node(source: .bytes(bytes))
            )))
        case .content:
            var inputs = inputs[self, \.content]

            inputs.environment.certificateProperty = .chain

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
