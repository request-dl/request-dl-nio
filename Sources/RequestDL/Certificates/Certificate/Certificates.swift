/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Certificates<Content: Property>: Property {

    private let content: Content

    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        bodyException()
    }
}

extension Certificates {

    private struct Node: SecureConnectionPropertyNode {

        let nodes: [Leaf<SecureConnectionNode>]

        func make(_ secureConnection: inout Internals.SecureConnection) {
            for node in nodes {
                node.passthrough(&secureConnection)
            }
        }
    }

    public static func _makeProperty(
        property: _GraphValue<Certificates<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        var inputs = inputs[self, \.content]
        inputs.environment.certificateProperty = .chain
        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .init(Leaf(SecureConnectionNode(
            Node(nodes: outputs.node
                .search(for: SecureConnectionNode.self)
                .filter { $0.contains(CertificateNode.self) }
            )
        )))
    }
}
