//
// See LICENSE for this package's licensing information.
//

/// A node in the resolved property graph.
///
/// Exposes its children rather than iterating itself. The previous shape, `mutating func
/// next()`, put traversal state inside the data: every walk had to copy the node first to
/// avoid consuming it, and correctness rested on every conformance being a value type, which
/// a protocol cannot require. A single `final class` conformance would have made the first
/// traversal eat the graph, and the second one find an empty tree with no error anywhere.
protocol Node: Sendable, NodeStringConvertible {

    var children: [Node] { get }
}

extension Node {

    var nodeDescription: String {
        let title = String(describing: type(of: self))
        let descriptions = children.map(\.nodeDescription)

        guard !descriptions.isEmpty else {
            return title
        }

        let childrenDescription =
            descriptions
            .joined(separator: ",\n")
            .debug_shiftLines()

        return "\(title) {\n\(childrenDescription)\n}"
    }
}

extension Node {

    func first<Property: PropertyNode>(
        of propertyNode: Property.Type
    ) -> LeafNode<Property>? {
        if let leaf = self as? LeafNode<Property> {
            return leaf
        }

        for child in children {
            if let property = child.first(of: propertyNode) {
                return property
            }
        }

        return nil
    }

    func search<Property: PropertyNode>(
        for propertyNode: Property.Type
    ) -> [LeafNode<Property>] {
        if let leaf = self as? LeafNode<Property> {
            return [leaf]
        }

        return children.flatMap {
            $0.search(for: propertyNode)
        }
    }
}
