/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct EnvironmentProperty<Content: Property>: Property {

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let content: Content
    let setter: @Sendable (inout PropertyEnvironmentValues) -> Void

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<EnvironmentProperty<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        var inputs = inputs
        property.setter(&inputs.environment)

        return try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )
    }
}

// MARK: - Property extension

extension Property {

    /**
     Sets an `Value` for a given `keyPath`.

     - Parameters:
       - keyPath: The `WritableKeyPath` of the ``PropertyEnvironmentValues`` to set the `value` for.
       - value: The `Value` to set for the ``PropertyEnvironment``.

     - Returns: A modified `Property` with the new ``PropertyEnvironmentValues`` set.
     */
    public func environment<Value: Sendable>(
        _ keyPath: WritableKeyPath<PropertyEnvironmentValues, Value> & Sendable,
        _ value: Value
    ) -> some Property {
        EnvironmentProperty(content: self) {
            $0[keyPath: keyPath] = value
        }
    }
}
