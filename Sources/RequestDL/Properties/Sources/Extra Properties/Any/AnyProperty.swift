/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A type-erasing wrapper that can represent any `Property` instance.
@RequestActor
public struct AnyProperty: Property {

    private let makeProperty: (_GraphValue<Self>, _PropertyInputs) async throws -> _PropertyOutputs

    /// Initializes a new instance of `AnyProperty` with the given property `Content`.
    public init<Content: Property>(_ property: Content) {
        self.makeProperty = { graph, inputs in
            try await Content._makeProperty(
                property: graph.detach(next: property),
                inputs: inputs
            )
        }
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension AnyProperty {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<AnyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return try await property.makeProperty(property, inputs)
    }
}
