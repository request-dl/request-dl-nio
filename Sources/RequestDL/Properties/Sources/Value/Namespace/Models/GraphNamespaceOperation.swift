//
// See LICENSE for this package's licensing information.
//

struct GraphNamespaceOperation<Content: Sendable>: GraphValueOperation {

    // MARK: - Private properties

    private let mirror: DynamicValueMirror<Content>

    // MARK: - Inits

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    // MARK: - Internal methods

    func callAsFunction(_ properties: inout GraphProperties) {
        let namespaces = mirror().compactMap { child -> (label: String, value: PropertyNamespace)? in
            guard let namespace = child.value as? PropertyNamespace else {
                return nil
            }

            return (child.label ?? "nil", namespace)
        }

        guard !namespaces.isEmpty else {
            return
        }

        // One merged namespace for every wrapper in the property, which is what the
        // documentation promises. Building it progressively left each wrapper holding a prefix
        // of the real namespace, so with `@PropertyNamespace var foo` followed by `var bar`,
        // reading `foo` reported `_foo` while `_foo._bar` was the one actually in effect.
        let namespaceID = PropertyNamespace.ID(
            base: Content.self,
            namespace: namespaces.map(\.label).joined(separator: ".")
        )

        for namespace in namespaces {
            namespace.value.id = namespaceID
        }

        properties.inputs.namespaceID = namespaceID
    }
}
