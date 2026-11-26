//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import CryptoKit
import Security
import SwiftAsyncStream
import Testing
import X509
import _CryptoExtras

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What `Internals.RawBytesIdentityBuilder.makeIdentity(certificateDER:privateKeyDER:)` builds:
/// a `SecIdentity` held in memory (`SecIdentityCreate`), with nothing stored in a Keychain.
///
/// The "nothing is stored" tests only ever look, and only by the attributes of a certificate and
/// a key generated for that very test (a unique common name, and the hash of its own public key):
/// they never write, and never read or touch an item they did not generate.
struct InternalsRawBytesIdentityBuilderIdentityTests {

    // MARK: - Nothing is stored

    @Test(arguments: Fixture.Kind.allCases)
    func makeIdentity_whenGivenAMatchingPair_storesNothingInEitherKeychain(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)
        fixture.expectNothingStored(before: true)

        // When
        let handle = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: fixture.certificateDER,
            privateKeyDER: fixture.keyDER
        )

        // Then
        withExtendedLifetime(handle) {
            fixture.expectNothingStored(before: false)
            #expect(fixture.canSign(with: handle.identity), "the identity cannot sign with its key")
        }

        fixture.expectNothingStored(before: false)
    }

    @Test(arguments: Fixture.Kind.allCases)
    func makeIdentity_whenTheHandleIsReleased_storesAndDeletesNothing(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)

        // When
        do {
            _ = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: fixture.certificateDER,
                privateKeyDER: fixture.keyDER
            )
        }

        // Then
        fixture.expectNothingStored(before: false)
    }

    // MARK: - Handles do not depend on each other

    /// The race that used to exist across processes (the login keychain is shared, so one
    /// process's release deleted the items another still used) as an invariant of one: two
    /// handles for the same pair share nothing, so releasing one leaves the other whole.
    @Test(arguments: Fixture.Kind.allCases)
    func release_whenAnotherHandleOfTheSamePairIsAlive_leavesItAbleToSign(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)

        var first: Internals.IdentityHandle? = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: fixture.certificateDER,
            privateKeyDER: fixture.keyDER
        )
        let second = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: fixture.certificateDER,
            privateKeyDER: fixture.keyDER
        )

        #expect(first !== second)
        #expect(first.map { fixture.canSign(with: $0.identity) } == true)

        // When
        first = nil

        // Then
        #expect(fixture.canSign(with: second.identity), "the surviving handle can no longer sign")
        fixture.expectNothingStored(before: false)
    }

    /// The same key in two encodings (PKCS#1 and PKCS#8) used to be one Keychain item with two
    /// owners that did not know about each other.
    @Test
    func release_whenTheSameKeyArrivedInAnotherEncoding_leavesTheOtherHandleAbleToSign() throws {
        // Given
        let fixture = try Fixture(.rsa)

        let second = try Self.makeSecondHandle(
            certificateDER: fixture.certificateDER,
            firstKeyDER: fixture.keyDER,
            secondKeyDER: fixture.pkcs8KeyDER
        )

        // Then
        #expect(fixture.canSign(with: second.identity))
    }

    // MARK: - The cleanup of the old keys

    /// What starts the cleanup (see `InternalsLegacyIdentityItemsTests`) runs once the identity
    /// exists, and changes nothing about it.
    @Test(arguments: Fixture.Kind.allCases)
    func makeIdentity_whenTheIdentityIsBuilt_startsTheCleanupAfterwards(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)
        var calls = 0

        // When
        let handle = try Internals.RawBytesIdentityBuilder.makeIdentity(
            certificateDER: fixture.certificateDER,
            privateKeyDER: fixture.keyDER,
            afterBuilding: { calls += 1 }
        )

        // Then
        #expect(calls == 1)
        #expect(fixture.canSign(with: handle.identity))
    }

    @Test(arguments: Fixture.Kind.allCases)
    func makeIdentity_whenTheIdentityCannotBeBuilt_doesNotStartTheCleanup(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)
        let other = try Fixture(kind)
        var calls = 0

        // When
        #expect(throws: Internals.RawBytesIdentityBuilder.Error.privateKeyDoesNotMatchCertificate) {
            _ = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: fixture.certificateDER,
                privateKeyDER: other.keyDER,
                afterBuilding: { calls += 1 }
            )
        }

        // Then
        #expect(calls == 0)
    }

    /// The real start of the cleanup: any number of builds, on any thread, in an unsigned process
    /// (where it finds nothing to do), returns at once and builds the identity.
    @Test
    func makeIdentity_whenBuiltFromManyThreads_buildsEveryIdentity() async throws {
        let fixture = try Fixture(.ec)

        let signed = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let handle = try Internals.RawBytesIdentityBuilder.makeIdentity(
                        certificateDER: fixture.certificateDER,
                        privateKeyDER: fixture.keyDER
                    )
                    return fixture.canSign(with: handle.identity)
                }
            }
            return try await group.reduce(into: [Bool]()) { $0.append($1) }
        }

        #expect(signed == Array(repeating: true, count: 8))
    }

    // MARK: - A key that is not the certificate's

    @Test(arguments: Fixture.Kind.allCases)
    func makeIdentity_whenTheKeyIsNotTheCertificates_throwsAndStoresNothing(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)
        let other = try Fixture(kind)

        // When
        do {
            _ = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: fixture.certificateDER,
                privateKeyDER: other.keyDER
            )
            Issue.record("Not expecting success")
        } catch Internals.RawBytesIdentityBuilder.Error.privateKeyDoesNotMatchCertificate {
            // Expected.
        }

        // Then
        fixture.expectNothingStored(before: false)
        other.expectNothingStored(before: false)
    }

    /// The operating system's own answer, which is what the error stands on when the public key
    /// bytes cannot be compared first: `SecIdentityCreate` refuses a key that is not the
    /// certificate's.
    @Test(arguments: Fixture.Kind.allCases)
    func secIdentityCreate_whenTheKeyIsNotTheCertificates_returnsNil(_ kind: Fixture.Kind) throws {
        // Given
        let fixture = try Fixture(kind)
        let other = try Fixture(kind)

        let certificate = try Internals.RawBytesIdentityBuilder.certificate(fromDER: fixture.certificateDER)
        let matching = try Internals.RawBytesIdentityBuilder.secKey(fromDER: fixture.keyDER)
        let notMatching = try Internals.RawBytesIdentityBuilder.secKey(fromDER: other.keyDER)

        // Then
        #expect(SecIdentityCreate(nil, certificate, matching) != nil)
        #expect(SecIdentityCreate(nil, certificate, notMatching) == nil)
    }

    @Test
    func makeIdentity_whenTheKeyIsNotTheCertificates_isReportedAsAKeyCreationFailureWithAClearMessage() throws {
        // Given
        let fixture = try Fixture(.rsa)
        let other = try Fixture(.rsa)

        // When
        do {
            _ = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: fixture.certificateDER,
                privateKeyDER: other.keyDER
            )
            Issue.record("Not expecting success")
        } catch let error as Internals.RawBytesIdentityBuilder.Error {
            // Then: what `RawTask` hands the caller, through `ClientIdentityError`'s own mapping.
            #expect(error.description.contains("not the one of the configured certificate"))
        }
    }

    // MARK: - A real handshake, with the surviving handle

    /// A handle that outlived another one for the same pair still authenticates against a server
    /// that requires a client certificate. RSA, from the checked-in fixtures.
    @Test
    func handshake_whenPresentedByTheHandleThatOutlivedAnother_authenticatesWithRSA() async throws {
        // Given
        let resource = Certificates().client()

        // When / Then
        try await Self.expectHandshake(resource: resource, port: 8951)
    }

    /// EC P-256, which could not be stored on the macOS file keychain of an unsigned process
    /// (`SecItemAdd` failed with `-25304`), authenticates for real now that nothing is stored.
    @Test
    func handshake_whenTheKeyIsEC_authenticatesWithoutAnyKeychainAccess() async throws {
        // Given
        let resource = Certificates().clientEC()

        // When / Then
        try await Self.expectHandshake(resource: resource, port: 8952)
    }

    // MARK: - Helpers

    /// The first handle is released when this returns, after the second one was built.
    private static func makeSecondHandle(
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

    /// The server of these handshakes verifies the client certificate
    /// (`LocalServer.TLSOption.client(_:)`), which has no Network.framework equivalent under a
    /// NIOCore-free build (see that type's own doc comment), where the server cannot even start.
    private static func expectHandshake(resource: CertificateResource, port: UInt) async throws {
        #if canImport(NIOCore)
        try await handshake(resource: resource, port: port)
        #else
        await withKnownIssue(
            """
            LocalServer.TLSOption.client(_:) (server-side mTLS verification) has no \
            Network.framework equivalent under a NIOCore-free build
            """
        ) {
            try await handshake(resource: resource, port: port)
        }
        #endif
    }

    private static func handshake(
        resource: CertificateResource,
        port: UInt
    ) async throws {
        let server = Certificates().server()
        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: port,
                option: .client(resource)
            )
        )

        let output = "Hello World"
        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .file(server.certificateURL.absolutePath(percentEncoded: false))

        let certificateDER = try Internals.Certificate.resolvedPEMCertificateDERBytes(
            of: Data(contentsOf: resource.certificateURL)
        )[0]
        let keyDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(
            from: .privateKey(
                .init(resource.privateKeyURL.absolutePath(percentEncoded: false), format: resource.format)
            )
        )

        // The first handle is released when this returns; the second one is what answers.
        let second = try Self.makeSecondHandle(
            certificateDER: certificateDER,
            firstKeyDER: keyDER,
            secondKeyDER: keyDER
        )

        let delegate = IdentityDelegate(
            identity: second.identity,
            serverTrustPolicy: try Internals.ServerTrustPolicy.resolve(from: secureConnection)
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)")))
        request.httpMethod = "GET"

        // When
        let (data, response) = try await session.data(for: request)

        // Then
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try HTTPResult<String>(data).response == output)
        #expect(delegate.presentedIdentity, "the server never asked for the client certificate")
    }

    /// A certificate and its key, generated for one test, with the attributes the Keychain would
    /// know them by.
    struct Fixture {

        enum Kind: CaseIterable, Sendable {
            case rsa
            case ec
        }

        let kind: Kind
        let certificateDER: Data

        /// PKCS#1 for RSA, the library's DER for EC.
        let keyDER: Data
        let pkcs8KeyDER: Data

        /// SHA-1 of the public key: what a key item is found by (`kSecAttrApplicationLabel`) and
        /// what a certificate item carries as `kSecAttrPublicKeyHash`.
        let publicKeyHash: Data

        init(_ kind: Kind) throws {
            self.kind = kind

            let commonName = "request-dl-test-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
            let name = try DistinguishedName { CommonName(commonName) }
            let now = Date()

            let publicKey: Certificate.PublicKey
            let issuerKey: Certificate.PrivateKey
            let signatureAlgorithm: Certificate.SignatureAlgorithm

            switch kind {
            case .rsa:
                let key = try _RSA.Signing.PrivateKey(keySize: .bits2048)
                publicKey = Certificate.PublicKey(key.publicKey)
                issuerKey = Certificate.PrivateKey(key)
                signatureAlgorithm = .sha256WithRSAEncryption
                keyDER = key.derRepresentation
                pkcs8KeyDER = key.pkcs8DERRepresentation

            case .ec:
                let key = P256.Signing.PrivateKey()
                publicKey = Certificate.PublicKey(key.publicKey)
                issuerKey = Certificate.PrivateKey(key)
                signatureAlgorithm = .ecdsaWithSHA256
                keyDER = key.derRepresentation
                pkcs8KeyDER = key.derRepresentation
            }

            let certificate = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: publicKey,
                notValidBefore: now.addingTimeInterval(-3_600),
                notValidAfter: now.addingTimeInterval(3_600),
                issuer: name,
                subject: name,
                signatureAlgorithm: signatureAlgorithm,
                extensions: Certificate.Extensions(),
                issuerPrivateKey: issuerKey
            )

            self.certificateDER = Data(try certificate.serializeAsPEM().derBytes)

            let secCertificate = try Internals.RawBytesIdentityBuilder.certificate(fromDER: certificateDER)
            let secPublicKey = try #require(SecCertificateCopyKey(secCertificate))
            let representation = try #require(SecKeyCopyExternalRepresentation(secPublicKey, nil) as Data?)
            self.publicKeyHash = Data(Insecure.SHA1.hash(data: representation))
        }

        var signatureAlgorithm: SecKeyAlgorithm {
            switch kind {
            case .rsa: .rsaSignatureMessagePKCS1v15SHA256
            case .ec: .ecdsaSignatureMessageX962SHA256
            }
        }

        // MARK: - Looking (attributes of this fixture only; never writes, never lists)

        /// Whether the data-protection or the legacy keychain holds anything for this fixture's
        /// key (by application label) or certificate (by public key hash). A process without the
        /// Keychain Sharing entitlement cannot query the data-protection one at all, and answers
        /// `errSecMissingEntitlement`: it has not found anything either.
        func expectNothingStored(before: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
            let when = before ? "before" : "after"
            let acceptable: Set<OSStatus> = [errSecItemNotFound, errSecMissingEntitlement]

            for dataProtection in [true, false] {
                let key = SecItemCopyMatching(
                    [
                        kSecClass: kSecClassKey,
                        kSecAttrApplicationLabel: publicKeyHash,
                        kSecUseDataProtectionKeychain: dataProtection,
                    ] as CFDictionary,
                    nil
                )
                let certificate = SecItemCopyMatching(
                    [
                        kSecClass: kSecClassCertificate,
                        kSecAttrPublicKeyHash: publicKeyHash,
                        kSecUseDataProtectionKeychain: dataProtection,
                    ] as CFDictionary,
                    nil
                )

                #expect(
                    acceptable.contains(key),
                    "a key item exists \(when) makeIdentity (data protection: \(dataProtection), status \(key))",
                    sourceLocation: sourceLocation
                )
                #expect(
                    acceptable.contains(certificate),
                    "a certificate item exists \(when) makeIdentity (data protection: \(dataProtection), status \(certificate))",
                    sourceLocation: sourceLocation
                )
            }
        }

        // MARK: - Using

        /// Signs with the identity's own private key, and verifies the signature with the
        /// certificate's public key: the key the identity holds is the certificate's, and it works.
        func canSign(with identity: SecIdentity) -> Bool {
            var privateKey: SecKey?
            var certificate: SecCertificate?

            guard
                SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess, let privateKey,
                SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
                let publicKey = SecCertificateCopyKey(certificate)
            else {
                return false
            }

            let message = Data("identity".utf8) as CFData

            guard let signature = SecKeyCreateSignature(privateKey, signatureAlgorithm, message, nil) else {
                return false
            }

            return SecKeyVerifySignature(publicKey, signatureAlgorithm, message, signature, nil)
        }
    }
}

/// Answers an mTLS handshake by hand: the client-certificate challenge with the identity under
/// test, and the server-trust one with the policy of the test's own trust roots.
private final class IdentityDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let identity: SecIdentity
    private let serverTrustPolicy: Internals.ServerTrustPolicy
    private let lock = Lock()
    private var _presentedIdentity = false

    var presentedIdentity: Bool {
        lock.withLock { _presentedIdentity }
    }

    init(identity: SecIdentity, serverTrustPolicy: Internals.ServerTrustPolicy) {
        self.identity = identity
        self.serverTrustPolicy = serverTrustPolicy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            serverTrustPolicy.handle(challenge: challenge, completionHandler: completionHandler)
            return
        }

        lock.withLock { _presentedIdentity = true }
        completionHandler(
            .useCredential,
            URLCredential(identity: identity, certificates: nil, persistence: .forSession)
        )
    }
}

#endif
