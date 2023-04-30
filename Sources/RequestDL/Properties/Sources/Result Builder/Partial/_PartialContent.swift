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

        let accumulatedOutput = try await Accumulated._makeProperty(
            property: property.accumulated,
            inputs: inputs
        )

        let nextOutput = try await Next._makeProperty(
            property: property.next,
            inputs: inputs
        )

        var children = ChildrenNode()

        children.append(accumulatedOutput.node)
        children.append(nextOutput.node)

        return .init(children)
    }
}
