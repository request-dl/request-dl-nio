/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct GraphOperation<Content> {

    private let pathway: Int
    private let mirror: DynamicValueMirror<Content>

    init(_ property: _GraphValue<Content>) where Content: Property {
        self.pathway = property.pathway
        self.mirror = .init(property.pointer())
    }

    init(
        pathway: Int,
        content: Content
    ) {
        self.pathway = pathway
        self.mirror = .init(content)
    }

    func callAsFunction(_ inputs: inout _PropertyInputs) {
        var properties = GraphProperties(
            inputs: inputs,
            pathway: pathway
        )

        for operation in operations {
            operation(&properties)
        }

        inputs = properties.inputs
    }
}

extension GraphOperation {

    var operations: [GraphValueOperation] {
        [
            GraphNamespaceOperation(mirror),
            GraphEnvironmentOperation(mirror)
        ]
    }
}
