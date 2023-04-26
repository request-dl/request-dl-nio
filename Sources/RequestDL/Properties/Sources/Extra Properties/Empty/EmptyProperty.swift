/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A struct representing an empty property.
public struct EmptyProperty: Property {

    /// Initializes an empty request.
    public init() {}

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension EmptyProperty {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<EmptyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertIfNeeded()
        return .init(EmptyLeaf())
    }
}
