/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
@RequestActor
public struct _PropertyModifier_Content<Modifier: PropertyModifier>: Property {

    typealias Inputs = (_GraphValue<Self>, _PropertyInputs)

    private let maker: (Inputs) async throws -> _PropertyOutputs

    init(_ maker: @escaping (Inputs) async throws -> _PropertyOutputs) {
        self.maker = maker
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<_PropertyModifier_Content<Modifier>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return try await property.maker((property, inputs))
    }
}
