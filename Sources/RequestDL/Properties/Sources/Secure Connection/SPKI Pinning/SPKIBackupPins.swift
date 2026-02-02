/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

/// A declarative property for specifying backup SPKI pins within a certificate pinning configuration.
///
/// Backup pins enable safe certificate rotation by pre-deploying hashes for upcoming certificates.
/// Connections will succeed if the server presents either a primary or backup pin.
///
/// - Critical: Backup pins are mandatory in production to prevent lockout during certificate rotation.
/// - Note: Must be used within an ``SPKIPinning`` block. See ``SPKIPinning`` for complete usage
///   examples and operational best practices.
public struct SPKIBackupPins<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let content: Content

    // MARK: - Inits

    /// Creates a backup pins declaration block containing Base64-encoded SPKI hashes for future use.
    ///
    /// - Parameter content: A property builder block returning one or more Base64-encoded SHA-256
    ///   hashes of certificates scheduled for future deployment.
    public init(
        @PropertyBuilder content: () -> Content
    ) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SPKIBackupPins>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        var inputs = inputs

        inputs.environment.spkiHashAnchor = .backup

        return try await Content._makeProperty(
            property: property.detach(next: property.content),
            inputs: inputs
        )
    }
}
