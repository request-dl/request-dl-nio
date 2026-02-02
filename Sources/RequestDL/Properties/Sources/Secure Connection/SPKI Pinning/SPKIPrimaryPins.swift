/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

/// A declarative property for specifying primary SPKI pins within a certificate pinning configuration.
///
/// Primary pins represent currently active production certificates that the client explicitly trusts.
/// These pins are validated against the server's leaf certificate during TLS handshake.
///
/// - Note: Must be used within an ``SPKIPinning`` block. See ``SPKIPinning`` for complete usage
///   examples and security considerations.
public struct SPKIPrimaryPins<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let content: Content

    // MARK: - Inits

    /// Creates a primary pins declaration block containing Base64-encoded SPKI hashes.
        ///
        /// - Parameter content: A property builder block returning one or more Base64-encoded SHA-256
        ///   hashes of currently active certificates.
        public init(
        @PropertyBuilder content: () -> Content
    ) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SPKIPrimaryPins>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        var inputs = inputs

        inputs.environment.spkiHashAnchor = .primary

        return try await Content._makeProperty(
            property: property.detach(next: property.content),
            inputs: inputs
        )
    }
}
