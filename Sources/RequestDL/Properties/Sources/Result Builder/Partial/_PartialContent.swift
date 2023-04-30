/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
@RequestActor
public struct _PartialContent<Accumulated: Property, Next: Property>: Property {

    public let accumulated: Accumulated
    public let next: Next

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension _PartialContent {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<_PartialContent<Accumulated, Next>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let accumulated = try await Accumulated._makeProperty(
            property: property.accumulated,
            inputs: inputs
        )

        let next = try await Next._makeProperty(
            property: property.next,
            inputs: inputs
        )

        var children = ChildrenNode()

        children.append(accumulated.node, grouping: property.accumulated.isPartialContent)
        children.append(next.node)

        return .children(children)
    }
}

private protocol _PartialContentReference {}

extension _PartialContent: _PartialContentReference {}

extension Property {

    fileprivate var isPartialContent: Bool {
        self is _PartialContentReference
    }
}
