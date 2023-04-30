/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
private struct ModifiedProperty<Content: Property, Modifier: PropertyModifier>: Property {

    let content: Content
    let modifier: Modifier

    var body: Never {
        bodyException()
    }

    @RequestActor
    static func _makeProperty(
        property: _GraphValue<ModifiedProperty<Content, Modifier>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let modifiedContent = _PropertyModifier_Content<Modifier> { graph, inputs in
            let id = ObjectIdentifier(Content.self)

            return try await Content._makeProperty(
                property: graph.detach(id, next: property.content),
                inputs: inputs
            )
        }

        var inputs = inputs

        let operation = GraphOperation(
            pathway: property.pathway,
            content: property.modifier
        )

        operation(&inputs)

        let id = ObjectIdentifier(Modifier.Body.self)
        let content = property.modifier.body(content: modifiedContent)

        return try await Modifier.Body._makeProperty(
            property: property.detach(id, next: content),
            inputs: inputs
        )
    }
}

extension Property {

    /**
     Returns a modified `Property` type based on the given `Modifier`.

     - Parameter modifier: The `Modifier` used to modify the `Property`.
     - Returns: A modified `Property` type.
     */
    public func modifier<Modifier: PropertyModifier>(
        _ modifier: Modifier
    ) -> some Property {
        ModifiedProperty(
            content: self,
            modifier: modifier
        )
    }
}
