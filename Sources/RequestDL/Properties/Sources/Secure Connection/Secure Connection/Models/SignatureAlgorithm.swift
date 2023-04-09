/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct SignatureAlgorithm: RawRepresentable, Hashable, Sendable {

    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    private init(_ signatureAlgorithm: NIOSSL.SignatureAlgorithm) {
        self.init(rawValue: signatureAlgorithm.rawValue)
    }
}

extension SignatureAlgorithm {

    public static let rsaPkcs1Sha1 = SignatureAlgorithm(.rsaPkcs1Sha1)
    public static let rsaPkcs1Sha256 = SignatureAlgorithm(.rsaPkcs1Sha256)
    public static let rsaPkcs1Sha384 = SignatureAlgorithm(.rsaPkcs1Sha384)
    public static let rsaPkcs1Sha512 = SignatureAlgorithm(.rsaPkcs1Sha512)
    public static let ecdsaSha1 = SignatureAlgorithm(.ecdsaSha1)
    public static let ecdsaSecp256R1Sha256 = SignatureAlgorithm(.ecdsaSecp256R1Sha256)
    public static let ecdsaSecp384R1Sha384 = SignatureAlgorithm(.ecdsaSecp384R1Sha384)
    public static let ecdsaSecp521R1Sha512 = SignatureAlgorithm(.ecdsaSecp521R1Sha512)
    public static let rsaPssRsaeSha256 = SignatureAlgorithm(.rsaPssRsaeSha256)
    public static let rsaPssRsaeSha384 = SignatureAlgorithm(.rsaPssRsaeSha384)
    public static let rsaPssRsaeSha512 = SignatureAlgorithm(.rsaPssRsaeSha512)
    public static let ed25519 = SignatureAlgorithm(.ed25519)
}

extension SignatureAlgorithm {

    func build() -> NIOSSL.SignatureAlgorithm {
        .init(rawValue: rawValue)
    }
}
