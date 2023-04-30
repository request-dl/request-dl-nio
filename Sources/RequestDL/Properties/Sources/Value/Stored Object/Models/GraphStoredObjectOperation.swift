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

        for stored in deepSearch(DynamicStoredObject.self) {
            stored.value.update(.init(
                namespaceID: properties.inputs.namespaceID,
                base: Content.self,
                pathway: properties.pathway,
                label: stored.label
            ))
        }
    }
}
