/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphStoredObjectOperation<Content>: GraphValueOperation {

    private let mirror: DynamicValueMirror<Content>

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    func callAsFunction(_ properties: inout GraphProperties) {
        let deepSearch = DynamicValueDeepSearch(mirror)
        let id = properties.inputs.namespaceID

        for stored in deepSearch(DynamicStoredObject.self) {
            stored.value.update(.init(
                id: id,
                label: stored.label,
                seed: properties.inputs.seedFactory(id),
                base: Content.self
            ))
        }
    }
}
