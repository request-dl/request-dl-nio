/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol Node: CustomDebugStringConvertible {

    mutating func next() -> Node?
}

extension Node {

    func first<Property: PropertyNode>(
        of propertyNode: Property.Type
    ) -> Leaf<Property>? {
        if let leaf = self as? Leaf<Property> {
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
    ) -> [Leaf<Property>] {
        if let leaf = self as? Leaf<Property> {
            return [leaf]
        }

        var mutableSelf = self
        var items = [Leaf<Property>]()

        while let node = mutableSelf.next() {
            items.append(contentsOf: node.search(for: propertyNode))
        }

        return items
    }
}

extension Node {

    var debugDescription: String {
        let title = String(describing: type(of: self))
        var mutableSelf = self
        var children = [String]()

        while let node = mutableSelf.next() {
            children.append(node.debugDescription)
        }

        if children.isEmpty {
            return title
        }

        let childrenDescription = children
            .joined(separator: ",\n")
            .debug_updateLinesByShifting(inline: false)

        return "\(title) {\n\(childrenDescription)\n}"
    }
}
