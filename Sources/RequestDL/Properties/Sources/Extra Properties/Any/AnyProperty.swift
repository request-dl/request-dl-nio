/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A type-erasing wrapper that can represent any `Property` instance.
public struct AnyProperty: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let makeProperty: @Sendable (_GraphValue<Self>, _PropertyInputs) async throws -> _PropertyOutputs

    // MARK: - Inits

    /// Initializes a new instance of `AnyProperty` with the given property `Content`.
    public init<Content: Property>(_ property: Content) {
        self.makeProperty = { graph, inputs in
            try await Content._makeProperty(
                property: graph.detach(next: property),
                inputs: inputs
            )
        }
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AnyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return try await property.makeProperty(property, inputs)
    }
}
