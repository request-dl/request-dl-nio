//
// See LICENSE for this package's licensing information.
//

// These tests write to the REAL login keychain of whoever runs them. Each one builds its own
// certificate and key (a fresh RSA key and a self-signed certificate with a unique subject), so
// nothing it stores is shared with another test or with the user's own items, and removes
// everything it can have stored in a `defer`, whether it passed or not. macOS only, and only the
// legacy (file) keychain an unsigned `swift test` process falls back to.

#if os(macOS)

import CryptoKit
import Security
import Testing
import X509
import _CryptoExtras

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What `Internals.RawBytesIdentityBuilder` leaves in the Keychain: items that outlive the
/// handles that own them, are deleted under a live handle, or are left behind by a build that
/// failed.
@Suite(.serialized)
struct InternalsRawBytesIdentityBuilderKeychainTests {

    // MARK: - Items shared by several handles

    /// The same key reaches the builder in different encodings (PKCS#1 and PKCS#8, or the
    /// decrypted form of a protected PEM and a plain PKCS#8), but the Keychain stores one item
    /// per key and one per certificate, whatever bytes they arrived as. Releasing the first
    /// handle must not remove the items the second one is built on.
    @Test
    func release_whenAnotherLiveHandleUsesTheSameKeyInAnotherEncoding_keepsItsKeychainItems() throws {
        // Given
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        // When: two handles for one certificate and one key, alive at the same time; then the
        // first one goes away.
        let second = try Self.buildSecondWhileFirstIsAlive(
            certificateDER: fixture.certificateDER,
            firstKeyDER: fixture.pkcs1,
            secondKeyDER: fixture.pkcs8
        )

        // Then: the survivor still has its Keychain items, and they still work.
        withExtendedLifetime(second) {
            #expect(fixture.hasPrivateKey, "the private key item was deleted under a live IdentityHandle")
            #expect(fixture.hasCertificate, "the certificate item was deleted under a live IdentityHandle")
            #expect(
                fixture.hasIdentity,
                "no identity for the certificate is left in the keychain under a live IdentityHandle"
            )
            #expect(fixture.canSign(with: second.identity), "the live handle's identity can no longer sign")
        }
    }

    @Test
    func release_whenEveryHandleOfTheSameKeyInAnotherEncodingIsGone_removesTheKeyAndTheCertificate() throws {
        // Given
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        // When
        try Self.buildTwoEncodingsAndRelease(
            certificateDER: fixture.certificateDER,
            firstKeyDER: fixture.pkcs1,
            secondKeyDER: fixture.pkcs8
        ) {
            #expect(fixture.hasPrivateKey)
        }

        // Then
        #expect(!fixture.hasPrivateKey, "the private key item outlived its last handle")
        #expect(!fixture.hasCertificate, "the certificate item outlived its last handle")
    }

    @Test
    func release_whenEveryHandleIsGone_removesTheKeyAndTheCertificate() throws {
        // Given
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        // When
        try Self.buildAndRelease(certificateDER: fixture.certificateDER, keyDER: fixture.pkcs8) {
            #expect(fixture.hasPrivateKey)
            #expect(fixture.hasCertificate)
        }

        // Then
        #expect(!fixture.hasPrivateKey, "the private key item outlived its last handle")
        #expect(!fixture.hasCertificate, "the certificate item outlived its last handle")
    }

    // MARK: - Failed builds

    /// A key that is not the certificate's (a plain misconfiguration) never pairs into an
    /// identity. Nothing may be stored for it: no handle exists whose release would delete it.
    @Test
    func makeIdentity_whenKeyDoesNotMatchCertificate_leavesNothingInTheKeychain() throws {
        // Given
        let fixture = try Fixture()
        let stranger = try Fixture.makeKeyDER()
        defer { fixture.cleanUp(alsoKeys: [stranger]) }

        // When
        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            _ = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: fixture.certificateDER,
                privateKeyDER: stranger
            )
        }

        // Then
        #expect(!fixture.hasPrivateKey(stranger), "the unrelated private key was left in the keychain")
        #expect(!fixture.hasCertificate, "the certificate was left in the keychain")
    }

    /// The same, for the last line of defense: whatever `store(...)` added before it found no
    /// identity is removed again, even when the key was not checked against the certificate
    /// beforehand.
    @Test
    func store_whenNoIdentityPairsTheCertificateAndTheKey_removesWhatItAdded() throws {
        // Given
        let fixture = try Fixture()
        let stranger = try Fixture.makeKeyDER()
        defer { fixture.cleanUp(alsoKeys: [stranger]) }

        let label = "RequestDL.test.\(UUID().uuidString)"

        // When
        #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
            _ = try Internals.RawBytesIdentityBuilder.store(
                certificate: try Internals.RawBytesIdentityBuilder.certificate(fromDER: fixture.certificateDER),
                secKey: try Internals.RawBytesIdentityBuilder.secKey(fromDER: stranger),
                label: label,
                useDataProtectionKeychain: false
            )
        }

        // Then
        #expect(!fixture.hasPrivateKey(stranger), "the private key was left in the keychain")
        #expect(!fixture.hasCertificate, "the certificate was left in the keychain")
    }

    /// A wrong key for a certificate whose real identity is already in the Keychain, and in use.
    /// The failed build must neither take that identity for its own (the certificate alone is
    /// what an identity is looked up by) nor remove anything the live handle needs.
    @Test
    func makeIdentity_whenKeyDoesNotMatchACertificateAlreadyInUse_failsAndKeepsTheLiveIdentity() throws {
        // Given
        let fixture = try Fixture()
        let stranger = try Fixture.makeKeyDER()
        defer { fixture.cleanUp(alsoKeys: [stranger]) }

        let live = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: fixture.certificateDER,
            privateKeyDER: fixture.pkcs1
        )

        // When
        withExtendedLifetime(live) {
            #expect(throws: Internals.RawBytesIdentityBuilder.Error.self) {
                _ = try Internals.RawBytesIdentityBuilder.makeIdentity(
                    certificateDER: fixture.certificateDER,
                    privateKeyDER: stranger
                )
            }

            // Then
            #expect(!fixture.hasPrivateKey(stranger), "the unrelated private key was left in the keychain")
            #expect(fixture.hasPrivateKey, "the live handle's private key is gone")
            #expect(fixture.hasCertificate, "the live handle's certificate is gone")
            #expect(fixture.canSign(with: live.identity), "the live handle's identity can no longer sign")
        }
    }

    // MARK: - Helpers

    /// The first handle is released when this returns, after the second one was built.
    private static func buildSecondWhileFirstIsAlive(
        certificateDER: Data,
        firstKeyDER: Data,
        secondKeyDER: Data
    ) throws -> Internals.IdentityHandle {
        let first = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: certificateDER,
            privateKeyDER: firstKeyDER
        )

        return try withExtendedLifetime(first) {
            try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: certificateDER,
                privateKeyDER: secondKeyDER
            )
        }
    }

    private static func buildTwoEncodingsAndRelease(
        certificateDER: Data,
        firstKeyDER: Data,
        secondKeyDER: Data,
        whileAlive: () -> Void
    ) throws {
        let second = try buildSecondWhileFirstIsAlive(
            certificateDER: certificateDER,
            firstKeyDER: firstKeyDER,
            secondKeyDER: secondKeyDER
        )
        withExtendedLifetime(second, whileAlive)
    }

    private static func buildAndRelease(
        certificateDER: Data,
        keyDER: Data,
        whileAlive: () -> Void
    ) throws {
        let handle = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: certificateDER,
            privateKeyDER: keyDER
        )
        withExtendedLifetime(handle, whileAlive)
    }
}

// MARK: - Fixture

extension InternalsRawBytesIdentityBuilderKeychainTests {

    /// A certificate, its key in the two encodings the builder is given, and what is needed to
    /// look for those items in the Keychain and to remove them.
    fileprivate struct Fixture {

        let commonName: String
        let certificateDER: Data
        let pkcs1: Data
        let pkcs8: Data

        init() throws {
            let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
            let commonName = "request-dl-test-\(UUID().uuidString)"
            let name = try DistinguishedName { CommonName(commonName) }
            let now = Date()

            let certificate = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: Certificate.PublicKey(key.publicKey),
                notValidBefore: now.addingTimeInterval(-3_600),
                notValidAfter: now.addingTimeInterval(3_600),
                issuer: name,
                subject: name,
                signatureAlgorithm: .sha256WithRSAEncryption,
                extensions: Certificate.Extensions(),
                issuerPrivateKey: Certificate.PrivateKey(key)
            )

            self.commonName = commonName
            self.certificateDER = Data(try certificate.serializeAsPEM().derBytes)
            self.pkcs1 = key.derRepresentation
            self.pkcs8 = key.pkcs8DERRepresentation
        }

        /// A fresh RSA key (PKCS#1), unrelated to any certificate.
        static func makeKeyDER() throws -> Data {
            try _RSA.Signing.PrivateKey(keySize: .bits2048).derRepresentation
        }

        // MARK: - Looking

        var hasPrivateKey: Bool {
            hasPrivateKey(pkcs1)
        }

        func hasPrivateKey(_ keyDER: Data) -> Bool {
            guard let applicationLabel = Self.applicationLabel(ofKeyDER: keyDER) else {
                return false
            }
            return SecItemCopyMatching(Self.privateKeyQuery(applicationLabel) as CFDictionary, nil) == errSecSuccess
        }

        var hasCertificate: Bool {
            !storedCertificates().isEmpty
        }

        var hasIdentity: Bool {
            let query: [CFString: Any] = [
                kSecClass: kSecClassIdentity,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecReturnRef: true,
                kSecUseDataProtectionKeychain: false,
            ]

            var result: CFTypeRef?
            guard
                SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                let identities = result as? [SecIdentity]
            else {
                return false
            }

            return identities.contains { identity in
                var certificate: SecCertificate?
                guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
                    return false
                }
                return (SecCertificateCopyData(certificate) as Data) == certificateDER
            }
        }

        func canSign(with identity: SecIdentity) -> Bool {
            var privateKey: SecKey?
            guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess, let privateKey else {
                return false
            }

            return SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                Data("identity".utf8) as CFData,
                nil
            ) != nil
        }

        // MARK: - Cleaning

        /// Removes every item this fixture (and `alsoKeys`) can have put in the keychain, however
        /// the library labelled them: keys by public-key hash, the certificate by subject.
        func cleanUp(alsoKeys: [Data] = []) {
            for keyDER in [pkcs1] + alsoKeys {
                guard let applicationLabel = Self.applicationLabel(ofKeyDER: keyDER) else {
                    continue
                }

                // The file keychain can hold more than one copy of a key.
                for _ in 0..<5 {
                    guard SecItemDelete(Self.privateKeyQuery(applicationLabel) as CFDictionary) == errSecSuccess else {
                        break
                    }
                }
            }

            // By reference, one at a time: a delete by attribute query could take more than the
            // fixture's own certificate with it.
            for certificate in storedCertificates() {
                SecItemDelete(
                    [
                        kSecClass: kSecClassCertificate,
                        kSecValueRef: certificate,
                        kSecUseDataProtectionKeychain: false,
                    ] as CFDictionary
                )
            }
        }

        /// The fixture's certificate in the keychain: found by its unique subject, and only kept
        /// when it is byte for byte this fixture's.
        private func storedCertificates() -> [SecCertificate] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassCertificate,
                kSecMatchSubjectContains: commonName,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecReturnRef: true,
                kSecUseDataProtectionKeychain: false,
            ]

            var result: CFTypeRef?
            guard
                SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                let certificates = result as? [SecCertificate]
            else {
                return []
            }

            return certificates.filter { (SecCertificateCopyData($0) as Data) == certificateDER }
        }

        private static func privateKeyQuery(_ applicationLabel: Data) -> [CFString: Any] {
            [
                kSecClass: kSecClassKey,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                kSecAttrApplicationLabel: applicationLabel,
                kSecUseDataProtectionKeychain: false,
            ]
        }

        /// SHA-1 of the public key's external representation: what the library sets as
        /// `kSecAttrApplicationLabel` on the key item.
        private static func applicationLabel(ofKeyDER keyDER: Data) -> Data? {
            guard
                let secKey = try? Internals.RawBytesIdentityBuilder.secKey(fromDER: keyDER),
                let publicKey = SecKeyCopyPublicKey(secKey),
                let representation = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
            else {
                return nil
            }
            return Data(Insecure.SHA1.hash(data: representation))
        }
    }
}

#endif
