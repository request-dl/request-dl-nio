/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
struct LeafNode<Property: PropertyNode>: Node {

    // MARK: - Private properties

    private let property: Property

    // MARK: - Inits

    init(_ property: Property) {
        self.property = property
    }

    // MARK: - Internal methods

    subscript<Value>(dynamicMember keyPath: KeyPath<Property, Value>) -> Value {
        property[keyPath: keyPath]
    }

    mutating func next() -> Node? {
        nil
    }
}

// MARK: - PropertyNode

extension LeafNode: PropertyNode {

    var nodeDescription: String {
        let title = String(describing: type(of: self))
        let values = propertyDescription.debug_shiftLines()
        return "\(title) {\n\(values)\n}"
    }

    private var propertyDescription: String {
        "property = \(property.nodeDescription)"
    }

    func make(_ make: inout Make) async throws {
        try await property.make(&make)
    }
}
