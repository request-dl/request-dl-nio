/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
struct Leaf<Property: PropertyNode>: Node {

    private let property: Property

    init(_ property: Property) {
        self.property = property
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Property, Value>) -> Value {
        property[keyPath: keyPath]
    }

    mutating func next() -> Node? {
        nil
    }
}

extension Leaf: PropertyNode {

    func make(_ make: inout Make) async throws {
        try await property.make(&make)
    }
}

extension Leaf {

    var debugDescription: String {
        """
        \(String(describing: type(of: self))) {
            property = \(
                property.debugDescription
                    .debug_updateLinesByShifting(8)
            )
        }
        """
    }
}

struct EmptyLeaf: Node {

    init() {}

    mutating func next() -> Node? {
        nil
    }
}
