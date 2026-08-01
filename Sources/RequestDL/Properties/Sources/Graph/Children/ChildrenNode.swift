//
// See LICENSE for this package's licensing information.
//

struct ChildrenNode: Node {

    // MARK: - Internal properties

    // The traversal cursor that used to live here is gone. It was state about *reading* the
    // node kept inside the node itself, which is what forced every walk to copy defensively.
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
