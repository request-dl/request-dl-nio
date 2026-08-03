//
// See LICENSE for this package's licensing information.
//

struct ChildrenNode: Node {

    // MARK: - Internal properties

    // No traversal cursor here. State about *reading* the node kept inside the node itself
    // would force every walk to copy defensively.
    private(set) var children: [Node] = []

    // MARK: - Inits

    init() {}

    // MARK: - Internal methods

    mutating func append(_ node: Node, grouping: Bool = false) {
        if grouping, let group = node as? ChildrenNode {
            children.append(contentsOf: group.children)
        } else {
            children.append(node)
        }
    }
}
