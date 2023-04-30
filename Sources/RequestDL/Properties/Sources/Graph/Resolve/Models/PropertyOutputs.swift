/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _PropertyOutputs {

    let node: Node

    init(_ node: Node) {
        self.node = node
    }
}

@RequestActor
extension _PropertyOutputs {

    static var empty: Self {
        .init(EmptyLeafNode())
    }

    static func leaf<Property: PropertyNode>(_ property: Property) -> Self {
        .init(LeafNode(property))
    }

    static func children(_ children: ChildrenNode) -> Self {
        .init(children)
    }
}
