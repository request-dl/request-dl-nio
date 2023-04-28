/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
@RequestActor
public struct _OptionalContent<Content: Property>: Property {

    private let source: Content?

    public var content: Content {
        source.unsafelyUnwrapped
    }

    init(_ content: Content?) {
        self.source = content
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension _OptionalContent {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<_OptionalContent<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .none:
            return .init(EmptyLeaf())
        case .some:
            return try await Content._makeProperty(
                property: property.content,
                inputs: inputs
            )
        }
    }
}
