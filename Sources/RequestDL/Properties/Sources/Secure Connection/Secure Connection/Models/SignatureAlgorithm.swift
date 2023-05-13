/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// Represents the signature algorithms used in `SecureConnection` configuration.
public struct SignatureAlgorithm: Sendable, RawRepresentable, Hashable {

    // MARK: - Public static properties

    /// RSA PKCS1 with SHA-1 signature algorithm.
    public static let rsaPkcs1Sha1 = SignatureAlgorithm(.rsaPkcs1Sha1)

    /// RSA PKCS1 with SHA-256 signature algorithm.
    public static let rsaPkcs1Sha256 = SignatureAlgorithm(.rsaPkcs1Sha256)

    /// RSA PKCS1 with SHA-384 signature algorithm.
    public static let rsaPkcs1Sha384 = SignatureAlgorithm(.rsaPkcs1Sha384)

    /// RSA PKCS1 with SHA-512 signature algorithm.
    public static let rsaPkcs1Sha512 = SignatureAlgorithm(.rsaPkcs1Sha512)

    /// ECDSA with SHA-1 signature algorithm.
    public static let ecdsaSha1 = SignatureAlgorithm(.ecdsaSha1)

    /// ECDSA with secp256r1 curve and SHA-256 signature algorithm.
    public static let ecdsaSecp256R1Sha256 = SignatureAlgorithm(.ecdsaSecp256R1Sha256)

    /// ECDSA with secp384r1 curve and SHA-384 signature algorithm.
    public static let ecdsaSecp384R1Sha384 = SignatureAlgorithm(.ecdsaSecp384R1Sha384)

    /// ECDSA with secp521r1 curve and SHA-512 signature algorithm.
    public static let ecdsaSecp521R1Sha512 = SignatureAlgorithm(.ecdsaSecp521R1Sha512)

    /// RSA PSS with RSAE (v1.5) encoding and SHA-256 signature algorithm.
    public static let rsaPssRsaeSha256 = SignatureAlgorithm(.rsaPssRsaeSha256)

    /// RSA PSS with RSAE (v1.5) encoding and SHA-384 signature algorithm.
    public static let rsaPssRsaeSha384 = SignatureAlgorithm(.rsaPssRsaeSha384)

    /// RSA PSS with RSAE (v1.5) encoding and SHA-512 signature algorithm.
    public static let rsaPssRsaeSha512 = SignatureAlgorithm(.rsaPssRsaeSha512)

    /// Ed25519 signature algorithm.
    public static let ed25519 = SignatureAlgorithm(.ed25519)

    // MARK: - Public properties

    public let rawValue: UInt16

    // MARK: - Inits

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    private init(_ signatureAlgorithm: NIOSSL.SignatureAlgorithm) {
        self.init(rawValue: signatureAlgorithm.rawValue)
    }

    // MARK: - Internal methods

    func build() -> NIOSSL.SignatureAlgorithm {
        .init(rawValue: rawValue)
    }
}
