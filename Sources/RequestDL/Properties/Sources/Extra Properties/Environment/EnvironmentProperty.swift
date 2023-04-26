/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct EnvironmentProperty<Content: Property, Value>: Property {

    let content: Content
    let keyPath: WritableKeyPath<EnvironmentValues, Value>
    let value: Value

    var body: Never {
        bodyException()
    }

    static func _makeProperty(
        property: _GraphValue<EnvironmentProperty<Content, Value>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertIfNeeded()

        var inputs = inputs
        inputs.environment[keyPath: property.keyPath] = property.value

        return try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )
    }
}

extension Property {

    /**
     Sets an `EnvironmentValue` for a given `keyPath`.

     - Parameters:
       - keyPath: The `WritableKeyPath` of the `EnvironmentValues` to set the `value` for.
       - value: The `Value` to set for the `EnvironmentValue`.

     - Returns: A modified `Property` with the new `EnvironmentValue` set.
     */
    public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> some Property {
        EnvironmentProperty(
            content: self,
            keyPath: keyPath,
            value: value
        )
    }
}
