/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol Node: Sendable, NodeStringConvertible {

    mutating func next() -> Node?
}

extension Node {

    var nodeDescription: String {
        let title = String(describing: type(of: self))
        var mutableSelf = self
        var children = [String]()

        while let node = mutableSelf.next() {
            children.append(node.nodeDescription)
        }

        if children.isEmpty {
            return title
        }

        let childrenDescription = children
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

        var mutableSelf = self

        while let node = mutableSelf.next() {
            if let property = node.first(of: propertyNode) {
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

        var mutableSelf = self
        var items = [LeafNode<Property>]()

        while let node = mutableSelf.next() {
            items.append(contentsOf: node.search(for: propertyNode))
        }

        return items
    }
}
