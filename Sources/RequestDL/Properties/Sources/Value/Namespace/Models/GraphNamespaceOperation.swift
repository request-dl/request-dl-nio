/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct GraphNamespaceOperation<Content>: GraphValueOperation {

    private let mirror: DynamicValueMirror<Content>

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    func callAsFunction(_ properties: inout GraphProperties) {
        var labels = [String]()
        var latestID: Namespace.ID?

        for child in mirror() {
            guard let namespace = child.value as? Namespace else {
                continue
            }

            labels.append(child.label ?? "nil")
            let namespaceID = Namespace.ID(
                base: Content.self,
                namespace: labels.joined(separator: "."),
                hashValue: properties.pathway
            )

            namespace.id = namespaceID
            latestID = namespaceID
        }

        if let namespaceID = latestID {
            properties.inputs.namespaceID = namespaceID
        }
    }
}
