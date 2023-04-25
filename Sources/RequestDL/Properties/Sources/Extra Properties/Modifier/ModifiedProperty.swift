/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct ModifiedProperty<Content: Property, Modifier: PropertyModifier>: Property {

    let content: Content
    let modifier: Modifier

    private var abstractModifiedContent: Modifier.Body {
        Internals.Log.failure(
            .accessingAbstractContent()
        )
    }

    var body: Never {
        bodyException()
    }

    static func _makeProperty(
        property: _GraphValue<ModifiedProperty<Content, Modifier>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let modifiedContent = _PropertyModifier_Content<Modifier> { inputs in
            try await Content._makeProperty(
                property: .root(property.content),
                inputs: .init(
                    root: Content.self,
                    body: \.self,
                    environment: inputs.environment
                )
            )
        }

        return try await Modifier.Body._makeProperty(
            property: property.dynamic {
                $0.modifier.body(content: modifiedContent)
            },
            inputs: inputs[self, \.abstractModifiedContent]
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
