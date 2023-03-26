/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

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

        if property.options == .default {
            context.append(Node(
                root: context.root,
                object: SecureConnectionNode {
                    $0.trustRoots = .default
                },
                children: []
            ))
        }

        for (index, certificate) in certificates.enumerated() {
            context.append(Node(
                root: context.root,
                object: SecureConnectionNode {
                    if index == .zero && property.options == nil {
                        certificate(.trust, secureConnection: &$0)
                    } else {
                        certificate(.additionalTrust, secureConnection: &$0)
                    }
                },
                children: []
            ))
        }
    }
}
