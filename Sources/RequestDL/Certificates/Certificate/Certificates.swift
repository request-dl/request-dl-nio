/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct Certificates<Content: Property>: Property {

    private let content: Content

    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        bodyException()
    }

    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async throws {
        let node = Node(
            root: context.root,
            object: EmptyObject(property),
            children: []
        )

        let newContext = Context(node)
        try await Content.makeProperty(property.content, newContext)

        let certificates = newContext
            .findCollection(CertificateNode.self)

        context.append(Node(
            root: context.root,
            object: SecureConnectionNode {
                for certificate in certificates {
                    certificate(.chain, secureConnection: &$0)
                }
            },
            children: []
        ))
    }
}
