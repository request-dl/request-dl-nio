/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
@RequestActor
struct LeafNode<Property: PropertyNode>: Node {

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

extension LeafNode: PropertyNode {

    func make(_ make: inout Make) async throws {
        try await property.make(&make)
    }
}

extension LeafNode {

    private var propertyDescription: String {
        "property = \(property.nodeDescription)"
    }

    var nodeDescription: String {
        let title = String(describing: type(of: self))
        let values = propertyDescription.debug_shiftLines()
        return "\(title) {\n\(values)\n}"
    }
}
