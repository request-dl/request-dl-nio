/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct ModifiedProperty<Content: Property, Modifier: PropertyModifier>: Property {

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let content: Content
    let modifier: Modifier

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<ModifiedProperty<Content, Modifier>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let modifiedContent = _PropertyModifier_Content<Modifier> { graph, inputs in
            try await Content._makeProperty(
                property: graph.detach(next: property.content),
                inputs: inputs
            )
        }

        var inputs = inputs

        let operation = GraphOperation(
            pathway: property.pathway,
            content: property.modifier
        )

        operation(&inputs)

        let content = property.modifier.body(content: modifiedContent)

        return try await Modifier.Body._makeProperty(
            property: property.detach(next: content),
            inputs: inputs
        )
    }
}

// MARK: - Property extension

extension Property {

    /**
     Returns a modified ``Property`` type based on the given ``PropertyModifier``.

     - Parameter modifier: The ``PropertyModifier`` used to modify the ``Property``.
     - Returns: A modified ``Property`` type.
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
