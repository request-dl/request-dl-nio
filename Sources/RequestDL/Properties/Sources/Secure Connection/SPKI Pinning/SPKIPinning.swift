/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

/// A declarative property for configuring SPKI-based certificate pinning in secure connections.
///
/// This property enables explicit trust validation of server certificates by pinning their
/// SubjectPublicKeyInfo (SPKI) hashes, providing protection against compromised Certificate Authorities.
///
/// Usage example:
/// ```swift
/// SecureConnection {
///     SPKIPinning(verification: .failRequest) {
///         SPKIPrimaryPins {
///             SPKIHash("klO23nSSyL6n4XyLZ3PzJGQfzZ3X3X3X3X3X3X3X3X3=")
///             SPKIHash("another-valid-hash")
///         }
///         SPKIBackupPins {
///             SPKIHash("backup-hash-for-rotation")
///         }
///     }
/// }
/// ```
///
/// - Note: Always include backup pins in production environments to prevent catastrophic lockout
///   during certificate rotation. See OWASP MSTG-NETWORK-4 for operational best practices.
/// - Warning: Pinning bypasses standard PKI trust validation. Use only for high-value endpoints
///   where CA compromise risk outweighs operational complexity.
/// - SeeAlso: ``SPKIPinningVerification``
public struct SPKIPinning<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {

        let verification: SPKIPinningVerification
        let nodes: [LeafNode<SPKIHashNode>]

        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            var tlsPinning = secureConnection.tlsPinning ?? SPKIPinningConfiguration(
                primaryPins: [],
                backupPins: []
            )

            tlsPinning.verification = verification

            for node in nodes {
                try node.passthrough(&tlsPinning)
            }

            secureConnection.tlsPinning = tlsPinning
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let verification: SPKIPinningVerification
    private let content: Content

    // MARK: - Inits

    /// Creates an SPKI pinning configuration with explicit verification policy.
    ///
    /// - Parameters:
    ///   - verification: Failure behavior when pin validation fails:
    ///     - `.failRequest`: Immediately terminate connections with invalid pins (production)
    ///     - `.logAndProceed`: Allow connections but log warnings (staging/debugging only)
    ///   - content: A property builder block containing `SPKIPrimaryPins` and `SPKIBackupPins` declarations.
    ///              Primary pins represent currently active certificates; backup pins enable
    ///              safe certificate rotation without service disruption.
    ///
    /// - Important: Production deployments must include non-empty backup pins. Omitting backup
    ///   pins risks complete service outage during routine certificate renewal.
    public init(
        verification: SPKIPinningVerification = .failRequest,
        @PropertyBuilder content: () -> Content
    ) {
        self.verification = verification
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SPKIPinning>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let outputs = try await Content._makeProperty(
            property: property.detach(next: property.content),
            inputs: inputs
        )

        return .leaf(
            SecureConnectionNode(
                Node(
                    verification: property.verification,
                    nodes: outputs.node
                        .search(for: SPKIHashNode.self)
                ),
                logger: inputs.environment.logger
            )
        )
    }
}
