/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphNamespaceOperation<Content>: GraphValueOperation {

    // MARK: - Private properties

    private let mirror: DynamicValueMirror<Content>

    // MARK: - Inits

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    // MARK: - Internal methods

    func callAsFunction(_ properties: inout GraphProperties) {
        var labels = [String]()
        var latestID: PropertyNamespace.ID?

        for child in mirror() {
            guard let namespace = child.value as? PropertyNamespace else {
                continue
            }

            labels.append(child.label ?? "nil")
            let namespaceID = PropertyNamespace.ID(
                base: Content.self,
                namespace: labels.joined(separator: ".")
            )

            namespace.id = namespaceID
            latestID = namespaceID
        }

        if let namespaceID = latestID {
            properties.inputs.namespaceID = namespaceID
        }
    }
}
