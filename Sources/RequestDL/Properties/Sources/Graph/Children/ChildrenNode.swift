/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct ChildrenNode: Node {

    private var nodes: [Node] = []
    private var index: Int = .zero

    init() {}

    mutating func append(_ node: Node, grouping: Bool = false) {
        if grouping, let group = node as? ChildrenNode {
            nodes.append(contentsOf: group.nodes)
        } else {
            nodes.append(node)
        }
    }

    mutating func next() -> Node? {
        guard nodes.indices.contains(index) else {
            return nil
        }

        defer { index += 1 }
        return nodes[index]
    }
}
