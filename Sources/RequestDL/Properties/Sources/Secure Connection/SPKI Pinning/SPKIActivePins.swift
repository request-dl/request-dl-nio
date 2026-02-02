/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Active SPKI pins for certificate pinning.
///
/// Represents currently deployed certificates in production.
public struct SPKIActivePins<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let content: Content

    /// Creates an active pins declaration block.
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SPKIActivePins>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        var inputs = inputs
        inputs.environment.spkiHashAnchor = .active

        return try await Content._makeProperty(
            property: property.detach(next: property.content),
            inputs: inputs
        )
    }
}
