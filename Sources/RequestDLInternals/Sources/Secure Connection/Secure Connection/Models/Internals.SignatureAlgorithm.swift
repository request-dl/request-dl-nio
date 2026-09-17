//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    /// Portable mirror of `NIOSSL.SignatureAlgorithm` (a raw `UInt16` wrapper), same shape as
    /// `RequestDL.SignatureAlgorithm`, which these static members are named to match.
    package struct SignatureAlgorithm: Sendable, RawRepresentable, Hashable {

        // MARK: - Internal static properties

        package static let rsaPkcs1Sha1 = SignatureAlgorithm(rawValue: 0x0201)
        package static let rsaPkcs1Sha256 = SignatureAlgorithm(rawValue: 0x0401)
        package static let rsaPkcs1Sha384 = SignatureAlgorithm(rawValue: 0x0501)
        package static let rsaPkcs1Sha512 = SignatureAlgorithm(rawValue: 0x0601)
        package static let ecdsaSha1 = SignatureAlgorithm(rawValue: 0x0203)
        package static let ecdsaSecp256R1Sha256 = SignatureAlgorithm(rawValue: 0x0403)
        package static let ecdsaSecp384R1Sha384 = SignatureAlgorithm(rawValue: 0x0503)
        package static let ecdsaSecp521R1Sha512 = SignatureAlgorithm(rawValue: 0x0603)
        package static let rsaPssRsaeSha256 = SignatureAlgorithm(rawValue: 0x0804)
        package static let rsaPssRsaeSha384 = SignatureAlgorithm(rawValue: 0x0805)
        package static let rsaPssRsaeSha512 = SignatureAlgorithm(rawValue: 0x0806)
        package static let ed25519 = SignatureAlgorithm(rawValue: 0x0807)

        // MARK: - Internal properties

        package let rawValue: UInt16

        // MARK: - Inits

        package init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> NIOSSL.SignatureAlgorithm {
            .init(rawValue: rawValue)
        }
        #endif
    }
}
