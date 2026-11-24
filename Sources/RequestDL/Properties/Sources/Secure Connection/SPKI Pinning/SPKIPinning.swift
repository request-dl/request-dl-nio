//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// SPKI-based certificate pinning configuration for secure connections.
///
/// Validates server identity by matching the certificate's public key structure against
/// pre-configured hashes. Prevents man-in-the-middle attacks from compromised Certificate Authorities.
///
/// Example:
/// ```swift
/// SecureConnection {
///     SPKIPinning(policy: .strict) {
///         SPKIHash("base64-encoded-active-pin")
///         SPKIHash("base64-encoded-backup-pin")
///     }
/// }
/// ```
///
/// - Warning: Always deploy non-empty backup pins in production to avoid lockout during certificate rotation.
///
/// - Important: An `SPKIPinning` that declares no ``SPKIHash`` at all (an empty `PropertyForEach`,
/// a false `if`, ...) throws when the request is resolved instead of silently pinning nothing, for
/// either policy.
///
/// - Warning: Combined with ``SecureConnection/verification(_:)`` set to ``CertificateVerification/none``,
/// the pins are enforced by Network.framework (``Session/enableNetworkFramework(_:)``) and **not** by
/// `.nio` or `.urlSession`, so the same request can be accepted by one executor and rejected by
/// another. `.none` opts out of trust evaluation, and on those two the pin check is part of it: BoringSSL
/// does not call the verification callback when verification is off, and the `URLSession` trust policy
/// returns before looking at the pins. Network.framework's custom verification runs before that opt-out
/// is looked at, so it still applies them. This is how each executor behaves, and RequestDL does not
/// change it: it logs a warning when it sees the combination. Remove `.verification(.none)` to have the
/// pins enforced everywhere.
///
/// - Note: Without `.verification(.none)`, pinning is enforced by every executor, including
/// Network.framework, which gets the same pin check through a custom trust evaluation.
public struct SPKIPinning<Content: Property>: Property {

    private struct Node: SecureConnectionPropertyNode {
        let policy: SPKIPinningPolicy
        let nodes: [LeafNode<SPKIHashNode>]

        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            // Every executor reads an empty pin set as "nothing to pin against" and validates the
            // chain alone, so `SPKIPinning(.strict)` over zero pins (an empty `PropertyForEach`, a
            // false `if`, ...) would silently turn pinning off instead of failing closed. `.audit`
            // is rejected too: with no pin there is nothing to compare against, so it could never
            // report a match or a mismatch, only look like a working migration window.
            guard !nodes.isEmpty else {
                throw Internals.SPKIPinningError()
            }

            // A pin whose digest doesn't decode (a typo in the Base64, or a digest of the wrong
            // length for its algorithm) can never match. The NIO executors would swallow that as
            // "no match" and the `.urlSession` executor throws, so it's rejected here, once, for
            // all of them: otherwise a mistyped backup pin only shows up as a lockout when the
            // certificate rotates, and a policy whose pins are all invalid either blocks every
            // connection (`.strict`) or lets every one through unnoticed (`.audit`).
            for node in nodes {
                _ = try node.hash.resolvedDigest()
            }

            secureConnection.tlsPinningPolicy = policy.build()
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
    ///   - content: Property builder containing `SPKIHash` declarations, including any backup pins.
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

        var inputs = inputs
        inputs.environment.isInsideSPKIPinning = true

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
