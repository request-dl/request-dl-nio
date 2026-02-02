/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

/// SPKI-based certificate pinning configuration for secure connections.
///
/// Validates server identity by matching the certificate's public key structure against
/// pre-configured hashes. Prevents man-in-the-middle attacks from compromised Certificate Authorities.
///
/// Example:
/// ```swift
/// SecureConnection {
///     SPKIPinning(policy: .strict) {
///         SPKIActivePins {
///             SPKIHash("base64-encoded-active-pin")
///         }
///         SPKIBackupPins {
///             SPKIHash("base64-encoded-backup-pin")
///         }
///     }
/// }
/// ```
///
/// - Warning: Always deploy non-empty backup pins in production to avoid lockout during certificate rotation.
public struct SPKIPinning<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {
        let policy: SPKIPinningPolicy
        let nodes: [LeafNode<SPKIHashNode>]

        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            secureConnection.tlsPinningPolicy = policy
            secureConnection.tlsPins = nodes.map(\.hash)
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let policy: SPKIPinningPolicy
    private let content: Content

    // MARK: - Initialization

    /// Creates an SPKI pinning configuration.
    ///
    /// - Parameters:
    ///   - policy: Failure behavior on pin mismatch (`.strict` for production, `.audit` for debugging).
    ///   - content: Property builder containing `SPKIActivePins` and `SPKIBackupPins` declarations.
    public init(
        policy: SPKIPinningPolicy = .strict,
        @PropertyBuilder content: () -> Content
    ) {
        self.policy = policy
        self.content = content()
    }

    // MARK: - Property graph integration

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
                    policy: property.policy,
                    nodes: outputs.node.search(for: SPKIHashNode.self)
                ),
                logger: inputs.environment.logger
            )
        )
    }
}
