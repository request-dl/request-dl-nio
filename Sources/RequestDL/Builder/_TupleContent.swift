/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
@available(*, deprecated, renamed: "_PartialContent")
public struct _TupleContent<T>: Property {

    let value: T
    private let resolve: (_GraphValue<Self>, _PropertyInputs, Self.Type) async throws -> _PropertyOutputs

    init(
        _ value: T,
        resolve: @escaping (_GraphValue<Self>, _PropertyInputs, Self.Type) async throws -> _PropertyOutputs
    ) {
        self.value = value
        self.resolve = resolve
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

@available(*, deprecated, renamed: "_PartialContent")
extension _TupleContent {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<_TupleContent<T>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        try await property.resolve(property, inputs, self)
    }
}
