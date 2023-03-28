/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A type-erasing wrapper that can represent any `Property` instance.
public struct AnyProperty: Property {

    private let makeProperty: () async throws -> _PropertyOutputs

    /// Initializes a new instance of `AnyProperty` with the given property `Content`.
    public init<Content: Property>(_ property: Content) {
        self.makeProperty = {
            let erased = Erased(body: property)
            let root = _GraphValue.root(erased)
            let inputs = _PropertyInputs(
                root: Erased<Content>.self,
                body: \.self
            )

            return try await Erased._makeProperty(
                property: root,
                inputs: inputs
            )
        }
    }

    public var body: Never {
        bodyException()
    }
}

extension AnyProperty {

    public static func _makeProperty(
        property: _GraphValue<AnyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return try await property.makeProperty()
    }
}

extension AnyProperty {

    fileprivate struct Erased<Body: Property>: Property {

        let body: Body
    }
}
