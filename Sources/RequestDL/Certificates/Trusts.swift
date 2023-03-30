/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Trusts<Content: Property>: Property {

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

    public static func _makeProperty(
        property: _GraphValue<Trusts<Content>>,
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
