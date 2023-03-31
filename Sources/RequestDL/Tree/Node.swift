/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol Node {

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
