/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _PropertyOutputs: Sendable {

    // MARK: - Internal static properties

    static var empty: Self {
        .init(EmptyLeafNode())
    }

    // MARK: - Internal properties

    let node: Node

    // MARK: - Inits

    fileprivate init(_ node: Node) {
        self.node = node
    }

    // MARK: - Internal static methods

    static func leaf<Property: PropertyNode>(_ property: Property) -> Self {
        .init(LeafNode(property))
    }

    static func children(_ children: ChildrenNode) -> Self {
        .init(children)
    }
}
