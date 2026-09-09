//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import CryptoKit
import NIOSSL
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

    // MARK: - Password-protected RSA (PKCS#1)

    /// The encrypted/plain pair is a real key, generated once with `openssl genrsa -aes256
    /// -passout pass:\(Self.encryptedRSAPassword) 2048` and `openssl rsa -in <that> -passin
    /// pass:... ` -- not hand-assembled the way the plain-PKCS#1/SEC1 fixtures above are, since
    /// there's no in-process way to produce the legacy `Proc-Type`/`DEK-Info` encrypted PEM form
    /// at all (`_RSA.Signing.PrivateKey` -- what production itself decrypts this with -- has no
    /// encrypt-to-PEM direction, only decrypt-from-PEM).
    @Test
    func privateKeyDER_whenGivenPasswordProtectedPKCS1RSAPEM_decryptsToSameDERAsThePlainKey() throws {
        let source = Internals.PrivateKeySource.privateKey(
            .init(
                Array(Self.encryptedRSAPEM.utf8),
                format: .pem,
                password: NIOSSLSecureBytes(Self.encryptedRSAPassword.utf8)
            )
        )

        let decryptedDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(from: source)
        let plainDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: Data(Self.plainRSAPEM.utf8))

        #expect(decryptedDER == plainDER)

        // The whole point of decrypting here at all: the result still has to actually build a
        // working `SecKey`, the same as any other RSA key this executor hands off to Security.
        let secKey = try Internals.RawBytesIdentityBuilder.secKey(fromDER: decryptedDER)
        #expect(Self.keyType(of: secKey) == (kSecAttrKeyTypeRSA as String))
    }

    @Test
    func privateKeyDER_whenGivenPasswordProtectedPKCS1RSAPEMWithWrongPassword_throwsUnsupportedKeyFormat() {
        let source = Internals.PrivateKeySource.privateKey(
            .init(
                Array(Self.encryptedRSAPEM.utf8),
                format: .pem,
                password: NIOSSLSecureBytes("not the right password".utf8)
            )
        )

        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            try Internals.RawBytesIdentityBuilder.privateKeyDER(from: source)
        }
    }

    /// `_RSA.Signing.PrivateKey(encryptedPEMRepresentation:passphraseCallback:)` -- the only
    /// encrypted-key entry point available -- takes a PEM string, never raw DER, so a
    /// password-protected key sourced as `.der` has no decryption path at all and must fail
    /// before even attempting one.
    @Test
    func privateKeyDER_whenGivenPasswordProtectedKeyInDERFormat_throwsUnsupportedKeyFormat() throws {
        let plainDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: Data(Self.plainRSAPEM.utf8))
        let source = Internals.PrivateKeySource.privateKey(
            .init(
                [UInt8](plainDER),
                format: .der,
                password: NIOSSLSecureBytes(Self.encryptedRSAPassword.utf8)
            )
        )

        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            try Internals.RawBytesIdentityBuilder.privateKeyDER(from: source)
        }
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

    fileprivate static let encryptedRSAPassword = "testpassword123"

    /// `openssl genrsa -aes256 -passout pass:testpassword123 -out key.pem 2048`
    fileprivate static let encryptedRSAPEM = """
        -----BEGIN RSA PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        DEK-Info: AES-256-CBC,B2B9857B451A6912AE8C66D3C7542B2C

        mV/lX3n3MWwfliaoPi7EOeri1SPRxUH1KTOrzrAYmf0e+A1ftNvz7EDD2qpvh6Pr
        dXb7BqbTSktZHJc8r2J7KZOZJ8KELd5Tp6OaEqzbBh4FtmAhJ1tfdtjN5J4MVzdS
        UPCr64vj7Bs06lGj4r+/S0xqC+QsR64/Ujdwv7KT7pwsSc4cw1mOSdcA+5R4YPNM
        HsKDBBKy+IooNY4zoq/ZTnXuUxfZ/4oPVGWB4wsztt7ULdTCexImSJufukQJ5MvZ
        kDGMIh4fe8Qax2wvZycfYRBuovOxfOav8cjCggMo9Z0utV8d0Fo2ca6NRm57Hv14
        vc0JdP2tdKc2t9FVWX/MI3H1CQiJLGXkU1Ev50Diuf+MPeSbCCqSDywsC/h1w8MB
        evS7ZVgWPBjhrF9g5BkiMUyq7FTX1SZ3hEXjVbGFlVm1OZQzu6WI3Ak61wIgNyt6
        W/eKqG6vnYAEsSGgNQ6e/bZh/2zB1pMv2B8G/Ujhtg6bM5LZQ0nTuGFeK3EFdkSG
        C9Uo5lYfT+bKZVBGsW2zRDC9LkMKeHkRYJ75EcmmV3So1nQ+njeRM1c95qX2DzPv
        2rtSZVWtZ2w59lsJKgu+ff5CNSfmY15lR3ksQBvc7zVdc0xGdGqHSp6LIo9JIBrF
        S6qzVpnTrovLCGGGWdMoJXGsjjTwrFpRWrWjZLRA9f5ncXa0fDajggy1btTpE8d8
        Or8IuZ+P1POqnNlON/8QUq/lxBkYdP+gECJKRibIbK2NkYlXX37xK0D5+PlC1zdX
        QHQFh0F5fImwJbpM7n2+nXLC6PILN9w3cARII2nZC/HLo5oEbCH62Gn9IDMQ6OvV
        1KIX+u0g8WAIDi/fIS4CglHLA1SiJQPDFATTs+Iftf6/Sft8u9rwpJB77IE6ZDDv
        hKAAagtWUNYUw0zgNFeH2rdgOP5gFlGErTDIDqKvS6ZB/2ybCYoOM/FiSTVu8+JH
        A/rvqTWPx6+szHdHbrGK6OQnJ4rWVXb/GFiasCS1M58DDIQ3BsUFyFkf5tq9AMJa
        GkkWYnoUG3TuSEamx34YkKlrsXj1nLlP6MDYNtmdTWbp0lgWrzIwxiPMdM8541H+
        tRJ9WikupoknK5g40++brvEJpdyVsc429w6ADIRCko6PvffAdg3uin6bS3sdIWpm
        36BAw9eO59nAfXUVRvtd4e+PVivgnQv51Hlv84v5Am3af5iiqz+boo1HauSEq/Xc
        SiNTYoDaMnYUqFD2YtEpVIbTnXnXFZKKqgOZhHnQRpRoC3HEbpuald8VLDg5mvpF
        tNlJOuIBhyjMtKx6Un2Z5IHTWK8YblqnxPPvp9+DcRRubUjFP2NxLyLisUzG3FGs
        1cAyMhmuYxvU7g7iJLzxHAM2mIgcN/1c+Kd2CUjxoa3to+1a8nzBtruA8PDfw4Bx
        EgbMVVDkDFPc/vmQ23VlB1V2uFyWbuFeUNnfnswenjyKyVpOa5XsBLamchDPEptf
        Z6FWFFdLM/1DAYhdtTROH36Po2suEqN/6qNuSlqZIvVkaA6nRQ5tnfp/t4Y7zhCv
        m++ZisgcVLP/EcgX8j5bGmOnjyfs9HKhpOA0FiYkjp0A/Kcst3Ci2z+Sa3wSe/D3
        -----END RSA PRIVATE KEY-----
        """

    /// The same key as ``encryptedRSAPEM``, decrypted once via
    /// `openssl rsa -in encrypted.pem -passin pass:testpassword123` -- kept alongside it as the
    /// independent "known good" DER these tests compare the decrypted result against.
    fileprivate static let plainRSAPEM = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEogIBAAKCAQEA6OnR4SnI47vjlIxbZ2slMYbodYpEHx3haepYOf4pm0CfxeyQ
        xrn8V4vRaG5bPQOSAg41nNIn19kf5iDERT5UsAGBlv9yKd2BSvZT50OfJdF6A4Xo
        nzkfhQ19eL8d4HVV7NxnyVMQLcqqkLqb3roKwEPyRT5yjcqIpAjM02e/L5PmuEI/
        0+ezdEmYHWI5NAIbVSWwScZuWepFneHehFLg74SIkbWusAoRw21ihboZXUGhUk8M
        sTqCjjl+4Ii6UF59NJPs+5m6u2kxgzKpfVPyeSluBiTpNB9s/7aCyCOrPvb3D6xQ
        7ta0w8ToZWMXFf0WanO4k9s9CZk+eevERLKsawIDAQABAoIBAHqYmKCsHdHBVEkc
        mAAXpbwsBq/X14OJdt0JPOdJoRzXJ0JHAu2Xd/uc3NzbOasj9fafBBlHhTFYWDIJ
        jUXlSS5bnJqeWrkunp+WiRNxxJNjb5XrJkapCq4+K40jC9bZ7CCA4yBVWG7B/oWv
        s9vIkWAiY6OO+z0nHkU5XJbqRPgFIJvfTIaKJnUjRPDcVQG++ePRLYvvl7aVWmht
        81voYVmpt6BvyY44jD7g4ZriQQ9tUSsLQDeF+3qfC+OO/8fPrR/X2FeXWehEBxU/
        rDcvyIEgCUp5Y8OdvQH240TH1c7l/kOf5IzYcfrokKnryDPECD1ise2BqBv3NTak
        2lRuRAECgYEA9XeEpVTnOr53xr74UQ9kaSah5F4+fk2MEw71c8SMFEzmuF/KSzBv
        NYxXv7Ngusa+QSwyCiSsedwyEbCgohr9Z7vzHu8Y74HjM9SPz3t6NUW4GL2zAXvx
        qWPlVmIQNaM6YRRMHgEcTc6HMSJo1t5sT5LCZ8dwfY8qADfW7+mMs6MCgYEA8uhm
        Yx7klxzP9kQLWPVygfQDbiNb+jbHgteHhUX7iiBlo/Lu4G0Q7WCLqI1zwm85Cnn4
        HhNlSM9HfzdObBskXzYZBrD1Q92inJqjUNA/YaWbDT/gOeic5guFYSaWWWrY/ENY
        TTGrNl572VIz0r5cj7zGz/dBRD7VOxFxUcsscJkCgYBP4iV46LiXlYTFWUDWoHu8
        /KWS/Fi6IeKEEUov8rbjpGMxfXsIHSsT8ihcarQAFM21x/xA8M5wmghxWVntZ3sw
        Vyo31vf2ef7Gz1Y936FV1Oqkopeu0/dBeREZm7BKxGQrU7+xxArCB4RXqSsVQi1d
        eBVsUKt7MSwqBgIc8ZSooQKBgGLxZRtE7ynac59FUjX3LKBgi7EmOAXwoE3civgv
        bGl0DtK8Vq8V3gpDBEAw9hEiCuMIkZd2oRAKVn4sQgZo++TIfWMrW4w8UEtn9dQq
        L1cQBNtdxHDyHk7aLIdJF37utdnzeJlg/POVgu8fu7pBDiUCaR03At/QlDyOO1Fs
        5/opAoGALyaUDeMa/eX5hNjS7y+5ozBBBiWFQnnLGJY5HB1qtb3ujljQS2aj7Tlt
        vVyXj9KNL3mWgC7r3S0SSMzLIizTRO7DM3Gu2UCTbYBbwRKtYfT0jHrtG31y8dau
        N//PITY6Xld3pjHHji5em50I5davZaIHlv3n9A4Gdl08GHSYTCA=
        -----END RSA PRIVATE KEY-----
        """

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
