/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct Trusts<Content: Property>: Property {

    private let options: TrustsOption?
    private let content: Content

    public init(@PropertyBuilder content: () -> Content) {
        self.options = nil
        self.content = content()
    }

    public init(_ options: TrustsOption, @PropertyBuilder content: () -> Content) {
        self.options = options
        self.content = content()
    }

    public var body: Never {
        bodyException()
    }
}

extension Trusts {

    private struct Node: SecureConnectionPropertyNode {
        
        let isDefault: Bool
        let nodes: [Leaf<SecureConnectionNode>]

        func make(_ secureConnection: inout Internals.SecureConnection) {
            secureConnection.trustRoots = isDefault ? .default : nil

            for node in nodes {
                node.passthrough(&secureConnection)
            }
        }
    }

    public static func _makeProperty(
        property: _GraphValue<Trusts<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        var inputs = inputs[self, \.content]

        let isDefault = property.options == .default
        inputs.environment.certificateProperty = isDefault ? .additionalTrust : .trust

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .init(Leaf(SecureConnectionNode(
            Node(
                isDefault: isDefault,
                nodes: outputs.node
                    .search(for: SecureConnectionNode.self)
                    .filter { $0.contains(CertificateNode.self) }
            )
        )))
    }
}
