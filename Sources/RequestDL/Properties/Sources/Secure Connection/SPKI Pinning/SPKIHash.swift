/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Crypto

/// An SPKI (SubjectPublicKeyInfo) hash for certificate pinning.
///
/// Encodes a cryptographic hash of a server's public key structure to enforce explicit
/// trust during TLS handshakes. The hash algorithm is specified by the generic parameter.
///
/// Validation guarantees:
/// - Valid Base64 encoding with correct padding
/// - Digest length matches the algorithm's expected size (32 bytes for SHA-256,
///   48 bytes for SHA-384, 64 bytes for SHA-512)
///
/// Example:
/// ```swift
/// let pin: SPKIHash<SHA256> = SPKIHash("base64-encoded-hash")
/// ```
///
/// Generate pins using OpenSSL:
/// ```bash
/// openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | \
///   openssl x509 -pubkey -noout | \
///   openssl pkey -pubin -outform der | \
///   openssl dgst -sha256 -binary | \
///   openssl base64 -A
/// ```
public struct SPKIHash<Algorithm: HashFunction>: Property {

    // MARK: - Public properties

    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: Internals.SPKIHashSource

    // MARK: - Initialization

    /// Creates an SPKI hash using SHA-256.
    ///
    /// - Parameter base64Encoded: Base64-encoded SHA-256 digest.
    public init<S: StringProtocol>(_ base64Encoded: S) where Algorithm == SHA256 {
        self.source = .base64String(String(base64Encoded))
    }

    /// Creates an SPKI hash from raw SHA-256 digest bytes.
    ///
    /// - Parameter data: Raw 32-byte SHA-256 digest.
    public init(_  data: Data) where Algorithm == SHA256 {
        self.source = .rawData(data)
    }

    /// Creates an SPKI hash from a Base64-encoded string.
    ///
    /// - Parameters:
    ///   - base64Encoded: Base64-encoded hash digest.
    ///   - algorithm: Hash algorithm (must match the generic parameter).
    public init<S: StringProtocol>(_ base64Encoded: S, algorithm: Algorithm.Type) {
        self.source = .base64String(String(base64Encoded))
    }

    /// Creates an SPKI hash from raw digest bytes.
    ///
    /// - Parameters:
    ///   - data: Raw hash digest bytes.
    ///   - algorithm: Hash algorithm (must match the generic parameter).
    public init(_ data: Data, algorithm: Algorithm.Type) {
        self.source = .rawData(data)
    }

    // MARK: - Property graph integration

    public static func _makeProperty(
        property: _GraphValue<SPKIHash>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let hash = Internals.SPKIHash(
            anchor: inputs.environment.spkiHashAnchor,
            source: property.source,
            algorithm: Algorithm.self
        )

        return .leaf(SPKIHashNode(hash: hash))
    }
}
