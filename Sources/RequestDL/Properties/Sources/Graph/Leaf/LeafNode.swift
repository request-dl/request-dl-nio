//
// See LICENSE for this package's licensing information.
//

@dynamicMemberLookup
struct LeafNode<Property: PropertyNode>: Node {

    // MARK: - Internal properties

    var children: [Node] { [] }

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
}

// MARK: - PropertyNode

extension LeafNode: PropertyNode {

    // Declared here on purpose. `LeafNode` conforms to both `Node` and `PropertyNode`, and both
    // supply a default `nodeDescription`. Removing this one does not fail to compile: it
    // silently falls back to the `Node` default, which lists children, finds none, and prints
    // the bare title.
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
