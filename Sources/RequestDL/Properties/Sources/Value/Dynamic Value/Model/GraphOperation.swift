/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphOperation<Content>: Sendable {

    // MARK: - Internal properties

    var operations: [GraphValueOperation] {
        [
            GraphNamespaceOperation(mirror),
            GraphEnvironmentOperation(mirror),
            GraphStoredObjectOperation(mirror)
        ]
    }

    // MARK: - Private properties

    private let pathway: Int
    private let mirror: DynamicValueMirror<Content>

    // MARK: - Inits

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

    // MARK: - Internal methods

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
