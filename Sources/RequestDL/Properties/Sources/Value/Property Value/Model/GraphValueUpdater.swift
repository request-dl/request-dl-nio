/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphValueUpdater<Content> {

    private let hashValue: Int
    private let content: Content

    init(_ property: _GraphValue<Content>) where Content: Property {
        self.hashValue = property.pathwayHashValue
        self.content = property.pointer()
    }

    init(
        hashValue: Int,
        content: Content
    ) {
        self.hashValue = hashValue
        self.content = content
    }

    func callAsFunction(_ inputs: _PropertyInputs) -> _PropertyInputs {
        var inputs = inputs

        let environmentUpdater = PropertyEnvironmentUpdater(content)
        environmentUpdater(inputs.environment)

        let namespaceUpdater = PropertyNamespaceUpdater(content)
        if let namespaceID = namespaceUpdater(hashValue) {
            inputs.namespaceID = namespaceID
        }

        return inputs
    }
}
