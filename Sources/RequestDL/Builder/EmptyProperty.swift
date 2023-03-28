/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A struct representing an empty request.
public struct EmptyProperty: Property {

    /// Initializes an empty request.
    public init() {}

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension EmptyProperty {

    public static func _makeProperty(
        property: _GraphValue<EmptyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(EmptyLeaf())
    }
}
