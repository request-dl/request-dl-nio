/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
public struct _PropertyOutputs {

    let node: Node

    fileprivate init(_ node: Node) {
        self.node = node
    }
}

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
