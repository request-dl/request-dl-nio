//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import CryptoKit
import Security
import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Covers `Internals.RawBytesIdentityBuilder.secKey(fromDER:)`'s own format classification --
/// RSA/PKCS#1, RSA/PKCS#8, EC/SEC1, EC/PKCS#8 -- independent of the Keychain round trip
/// `makeIdentity(certificateDER:privateKeyDER:)` wraps around it. That round trip is a confirmed,
/// unconditional `withKnownIssue` on this SwiftPM test harness regardless of key type (no Keychain
/// Sharing entitlement -- see `RequestConfigurationURLSessionClientMTLSTests`'s own doc comment),
/// so testing the actual new logic here, which needs no Keychain access at all
/// (`SecKeyCreateWithData` builds an ephemeral, non-persistent `SecKey` purely in memory), is what
/// actually proves PKCS#8/EC support works, in an environment where the full round trip can't.
///
/// Test fixtures are generated fresh per run rather than checked in as static files: RSA keys via
/// `SecKeyCreateRandomKey` (no Keychain persistence needed since `kSecAttrIsPermanent` isn't set),
/// EC keys via `CryptoKit`. `DERWriter`/PKCS#8- and SEC1-shaping below is the deliberate inverse of
/// production's own minimal `DERReader` -- confirmed correct against `SecKeyCreateWithData`/
/// `CryptoKit`'s own encoders, not just internally consistent with itself.
struct InternalsRawBytesIdentityBuilderTests {

    // MARK: - RSA

    @Test
    func secKey_whenGivenBarePKCS1RSADER_succeeds() throws {
        let pkcs1 = try Self.makeRSAPKCS1DER()

        let secKey = try Internals.RawBytesIdentityBuilder.secKey(fromDER: pkcs1)

        #expect(Self.keyType(of: secKey) == (kSecAttrKeyTypeRSA as String))
    }

    @Test
    func secKey_whenGivenPKCS8WrappedRSADER_succeeds() throws {
        let pkcs1 = try Self.makeRSAPKCS1DER()
        let pkcs8 = Self.pkcs8(wrapping: pkcs1, algorithmOID: Self.rsaEncryptionOID)

        // Confirms the premise this test (and the production unwrap step) exists for: Security
        // itself does not accept a PKCS#8-wrapped RSA key directly.
        #expect(SecKeyCreateWithData(pkcs8 as CFData, Self.rsaAttributes as CFDictionary, nil) == nil)

        let secKey = try Internals.RawBytesIdentityBuilder.secKey(fromDER: pkcs8)

        #expect(Self.keyType(of: secKey) == (kSecAttrKeyTypeRSA as String))
    }

    @Test
    func privateKeyDER_whenGivenPKCS1PEM_stripsArmor() throws {
        let pkcs1 = try Self.makeRSAPKCS1DER()
        let pem = Self.pem(der: pkcs1, header: "RSA PRIVATE KEY")

        let der = try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: pem)

        #expect(der == pkcs1)
    }

    @Test
    func privateKeyDER_whenGivenPKCS8PEM_stripsArmor() throws {
        let pkcs1 = try Self.makeRSAPKCS1DER()
        let pkcs8 = Self.pkcs8(wrapping: pkcs1, algorithmOID: Self.rsaEncryptionOID)
        let pem = Self.pem(der: pkcs8, header: "PRIVATE KEY")

        let der = try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: pem)

        #expect(der == pkcs8)
    }

    // MARK: - EC

    @Test(arguments: [Self.Curve.p256, .p384, .p521])
    func secKey_whenGivenBareSEC1ECDERWithPublicKey_succeeds(_ curve: Self.Curve) throws {
        let scalar = curve.randomScalar()
        let publicKeyPoint = curve.x963PublicKey(fromScalar: scalar)
        let sec1 = Self.sec1ECPrivateKeyDER(scalar: scalar, curveOID: curve.oid, publicKeyPoint: publicKeyPoint)

        let secKey = try Internals.RawBytesIdentityBuilder.secKey(fromDER: sec1)

        #expect(Self.keyType(of: secKey) == (kSecAttrKeyTypeECSECPrimeRandom as String))
        #expect(Self.keySizeInBits(of: secKey) == curve.keySizeInBits)
    }

    /// SEC1's own `publicKey` field is optional -- a real-world EC key can omit it, and
    /// `secKey(fromDER:)` (via CryptoKit) must derive the public point from the private scalar
    /// alone rather than require it. Distinct from the test above, not redundant with it.
    @Test(arguments: [Self.Curve.p256, .p384, .p521])
    func secKey_whenGivenBareSEC1ECDERWithoutPublicKey_derivesItAndSucceeds(_ curve: Self.Curve) throws {
        let scalar = curve.randomScalar()
        let sec1 = Self.sec1ECPrivateKeyDER(scalar: scalar, curveOID: curve.oid, publicKeyPoint: nil)

        let secKey = try Internals.RawBytesIdentityBuilder.secKey(fromDER: sec1)

        #expect(Self.keyType(of: secKey) == (kSecAttrKeyTypeECSECPrimeRandom as String))
        #expect(Self.keySizeInBits(of: secKey) == curve.keySizeInBits)
    }

    @Test(arguments: [Self.Curve.p256, .p384, .p521])
    func secKey_whenGivenPKCS8WrappedECDER_succeeds(_ curve: Self.Curve) throws {
        // `CryptoKit`'s own `derRepresentation` -- confirmed PKCS#8 (a `SEQUENCE` containing an
        // `INTEGER` then a nested `SEQUENCE` AlgorithmIdentifier, not SEC1's `OCTET STRING`), not
        // assumed -- is exactly what a real caller exporting a CryptoKit-generated key would hand
        // this executor.
        let der = curve.generateAndExportPKCS8DER()

        let secKey = try Internals.RawBytesIdentityBuilder.secKey(fromDER: der)

        #expect(Self.keyType(of: secKey) == (kSecAttrKeyTypeECSECPrimeRandom as String))
        #expect(Self.keySizeInBits(of: secKey) == curve.keySizeInBits)
    }

    @Test
    func privateKeyDER_whenGivenSEC1PEM_stripsArmor() throws {
        let scalar = Self.Curve.p256.randomScalar()
        let publicKeyPoint = Self.Curve.p256.x963PublicKey(fromScalar: scalar)
        let sec1 = Self.sec1ECPrivateKeyDER(
            scalar: scalar,
            curveOID: Self.Curve.p256.oid,
            publicKeyPoint: publicKeyPoint
        )
        let pem = Self.pem(der: sec1, header: "EC PRIVATE KEY")

        let der = try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: pem)

        #expect(der == sec1)
    }

    // MARK: - Unsupported formats

    @Test
    func secKey_whenGivenGarbageBytes_throwsUnsupportedKeyFormat() {
        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            try Internals.RawBytesIdentityBuilder.secKey(fromDER: Data([0xFF, 0x00, 0x01, 0x02]))
        }
    }

    /// Curve25519 has no `SecKeyCreateWithData` entry point at all, and CryptoKit's `Curve25519`
    /// types have no DER export to even attempt -- so a real, well-formed key of a genuinely
    /// unsupported kind is exercised here via its raw scalar instead, confirming the cascade
    /// fails closed on it rather than misidentifying it as something else.
    @Test
    func secKey_whenGivenCurve25519RawKey_throwsUnsupportedKeyFormat() {
        let key = Curve25519.Signing.PrivateKey()

        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            try Internals.RawBytesIdentityBuilder.secKey(fromDER: key.rawRepresentation)
        }
    }

    @Test
    func privateKeyDER_whenGivenUnrecognizedPEMHeader_throwsUnsupportedKeyFormat() {
        let pem = Data("-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----".utf8)

        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: pem)
        }
    }
}

// MARK: - Test fixture construction

extension InternalsRawBytesIdentityBuilderTests {

    fileprivate static var rsaAttributes: [CFString: Any] {
        [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
    }

    fileprivate static func keyType(of secKey: SecKey) -> String? {
        (SecKeyCopyAttributes(secKey) as? [CFString: Any])?[kSecAttrKeyType] as? String
    }

    fileprivate static func keySizeInBits(of secKey: SecKey) -> Int? {
        (SecKeyCopyAttributes(secKey) as? [CFString: Any])?[kSecAttrKeySizeInBits] as? Int
    }

    /// A fresh, ephemeral 2048-bit RSA key's PKCS#1 DER, generated purely in memory --
    /// `kSecAttrIsPermanent` is deliberately left unset, so nothing here touches the Keychain.
    fileprivate static func makeRSAPKCS1DER() throws -> Data {
        var error: Unmanaged<CFError>?
        guard
            let key = SecKeyCreateRandomKey(
                [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary,
                &error
            )
        else {
            throw try #require(error).takeRetainedValue()
        }
        guard let der = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw try #require(error).takeRetainedValue()
        }
        return der
    }

    fileprivate static func pem(der: Data, header: String) -> Data {
        let base64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Data(
            """
            -----BEGIN \(header)-----
            \(base64)
            -----END \(header)-----
            """.utf8
        )
    }

    fileprivate static let rsaEncryptionOID: [UInt8] = [
        0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
    ]

    /// PKCS#8's `PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE, privateKey
    /// OCTET STRING }`, hand-assembled -- the deliberate inverse of production's own `DERReader`
    /// unwrap, confirmed correct via the round trip these tests actually run, not just by
    /// construction.
    fileprivate static func pkcs8(wrapping innerKeyDER: Data, algorithmOID: [UInt8]) -> Data {
        let algorithmIdentifier = DERWriter.sequence([algorithmOID, DERWriter.null])
        return Data(
            DERWriter.sequence([
                DERWriter.integer(0),
                algorithmIdentifier,
                DERWriter.octetString([UInt8](innerKeyDER)),
            ])
        )
    }

    /// SEC1's `ECPrivateKey ::= SEQUENCE { version INTEGER, privateKey OCTET STRING, [0]
    /// parameters ECParameters OPTIONAL, [1] publicKey BIT STRING OPTIONAL }`. `publicKeyPoint`
    /// (X9.63 `04 || X || Y`) is genuinely optional, matching the real ASN.1 grammar -- see
    /// `secKey_whenGivenBareSEC1ECDERWithoutPublicKey_derivesItAndSucceeds`.
    fileprivate static func sec1ECPrivateKeyDER(scalar: Data, curveOID: [UInt8], publicKeyPoint: Data?) -> Data {
        var children: [[UInt8]] = [
            DERWriter.integer(1),
            DERWriter.octetString([UInt8](scalar)),
            DERWriter.explicit(0, curveOID),
        ]
        if let publicKeyPoint {
            children.append(DERWriter.explicit(1, DERWriter.bitString([UInt8](publicKeyPoint))))
        }
        return Data(DERWriter.sequence(children))
    }

    /// The three NIST prime curves this executor's EC support targets, plus everything needed to
    /// build fixtures for each without relying on a single hardcoded curve.
    enum Curve: CaseIterable, CustomStringConvertible {
        case p256, p384, p521

        var description: String {
            switch self {
            case .p256: return "P256"
            case .p384: return "P384"
            case .p521: return "P521"
            }
        }

        var keySizeInBits: Int {
            switch self {
            case .p256: return 256
            case .p384: return 384
            case .p521: return 521
            }
        }

        /// DER-encoded `namedCurve` OBJECT IDENTIFIER for each curve (`ansip256r1`/`ansip384r1`/
        /// `ansip521r1`, a.k.a. `prime256v1`/`secp384r1`/`secp521r1`).
        var oid: [UInt8] {
            switch self {
            case .p256: return [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
            case .p384: return [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22]
            case .p521: return [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23]
            }
        }

        func randomScalar() -> Data {
            switch self {
            case .p256: return P256.Signing.PrivateKey().rawRepresentation
            case .p384: return P384.Signing.PrivateKey().rawRepresentation
            case .p521: return P521.Signing.PrivateKey().rawRepresentation
            }
        }

        func x963PublicKey(fromScalar scalar: Data) -> Data {
            switch self {
            case .p256: return (try! P256.Signing.PrivateKey(rawRepresentation: scalar)).publicKey.x963Representation
            case .p384: return (try! P384.Signing.PrivateKey(rawRepresentation: scalar)).publicKey.x963Representation
            case .p521: return (try! P521.Signing.PrivateKey(rawRepresentation: scalar)).publicKey.x963Representation
            }
        }

        func generateAndExportPKCS8DER() -> Data {
            switch self {
            case .p256: return P256.Signing.PrivateKey().derRepresentation
            case .p384: return P384.Signing.PrivateKey().derRepresentation
            case .p521: return P521.Signing.PrivateKey().derRepresentation
            }
        }
    }
}

/// Minimal DER TLV writer -- the deliberate inverse of production's `DERReader`
/// (`Internals.RawBytesIdentityBuilder.swift`), used only to hand-assemble PKCS#8/SEC1 test
/// fixtures. Not shipped: this lives in the test target only.
private enum DERWriter {

    static func tlv(tag: UInt8, content: [UInt8]) -> [UInt8] {
        var result: [UInt8] = [tag]
        if content.count < 0x80 {
            result.append(UInt8(content.count))
        } else {
            var lengthBytes: [UInt8] = []
            var length = content.count
            while length > 0 {
                lengthBytes.insert(UInt8(length & 0xFF), at: 0)
                length >>= 8
            }
            result.append(0x80 | UInt8(lengthBytes.count))
            result.append(contentsOf: lengthBytes)
        }
        result.append(contentsOf: content)
        return result
    }

    static func sequence(_ children: [[UInt8]]) -> [UInt8] {
        tlv(tag: 0x30, content: children.flatMap { $0 })
    }

    static func integer(_ value: UInt8) -> [UInt8] {
        tlv(tag: 0x02, content: [value])
    }

    static func octetString(_ bytes: [UInt8]) -> [UInt8] {
        tlv(tag: 0x04, content: bytes)
    }

    /// A BIT STRING with zero unused bits -- every use here wraps a byte-aligned EC point.
    static func bitString(_ bytes: [UInt8]) -> [UInt8] {
        tlv(tag: 0x03, content: [0x00] + bytes)
    }

    /// EXPLICIT context-specific tagging (`[n]`) -- `content` is the complete inner TLV
    /// (including its own tag and length), wrapped in an outer `0xA0 | n` tag.
    static func explicit(_ number: UInt8, _ content: [UInt8]) -> [UInt8] {
        tlv(tag: 0xA0 | number, content: content)
    }

    static let null: [UInt8] = [0x05, 0x00]
}

#endif
