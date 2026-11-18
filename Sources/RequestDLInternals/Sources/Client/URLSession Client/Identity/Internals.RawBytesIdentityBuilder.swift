//
// See LICENSE for this package's licensing information.
//

// Supports RSA (PKCS#1 or PKCS#8) and EC P-256/P-384/P-521 (SEC1 or PKCS#8) private keys,
// unencrypted, plus password-protected traditional PKCS#1 RSA PEM keys specifically,
// decrypted via `_CryptoExtras` (see `privateKeyDER(from:)`).

#if canImport(Darwin)

import CryptoKit
import Security
import SwiftASN1
import _CryptoExtras

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    /// Builds a `SecIdentity` (a `URLSession`-presentable client certificate) from raw
    /// certificate + private key bytes, in memory, with `SecIdentityCreate`: no Keychain item is
    /// ever added, queried or deleted. See `Internals.URLSessionIdentityPolicy` for how this turns
    /// an `Internals.SecureConnection` into per-host TLS challenge handling.
    package enum RawBytesIdentityBuilder {

        package enum Error: Swift.Error, CustomStringConvertible, Equatable, Sendable {
            case invalidCertificateData
            case unsupportedKeyFormat(String)
            case secKeyCreationFailed(String)

            /// The private key is not the one of the certificate: no identity can be built from them.
            case privateKeyDoesNotMatchCertificate

            /// The certificate's public key cannot be read: its algorithm or curve is not one
            /// Security supports (RSA-PSS keys, brainpool or secp256k1 curves, ...).
            case unsupportedCertificatePublicKey

            package var description: String {
                switch self {
                case .invalidCertificateData:
                    return "Could not parse the certificate data into a SecCertificate."
                case .unsupportedKeyFormat(let detail):
                    return """
                        Unsupported private key format (\(detail)). Supported for mTLS under the \
                        URLSession executor: RSA (PKCS#1 "-----BEGIN RSA PRIVATE KEY-----" or \
                        PKCS#8 "-----BEGIN PRIVATE KEY-----") and EC P-256/P-384/P-521 (SEC1 \
                        "-----BEGIN EC PRIVATE KEY-----" or PKCS#8 \
                        "-----BEGIN PRIVATE KEY-----"), unencrypted. A password-protected key is \
                        only supported for traditional PKCS#1 RSA PEM \
                        ("-----BEGIN RSA PRIVATE KEY-----" with "Proc-Type"/"DEK-Info" headers), \
                        not PKCS#8's "-----BEGIN ENCRYPTED PRIVATE KEY-----", and not any \
                        password-protected EC key.
                        """
                case .secKeyCreationFailed(let message):
                    return "SecKeyCreateWithData failed: \(message)."
                case .privateKeyDoesNotMatchCertificate:
                    return "The private key is not the one of the configured certificate (their public keys differ)."
                case .unsupportedCertificatePublicKey:
                    return
                        "The public key of the configured certificate cannot be read: its algorithm or curve is not supported (RSA and EC P-256/P-384/P-521 are)."
                }
            }
        }

        // MARK: - Identity sources (CertificateChain/PrivateKeySource -> raw DER bytes)
        //
        // Shared by every executor that needs a `SecIdentity` built from an
        // `Internals.SecureConnection`'s `certificateChain`/`privateKey`: `.urlSession`
        // (`Internals.URLSessionIdentityPolicy`) and `.nio` under Network.framework
        // (`Internals.SecureConnection.makeLocalIdentityForNetworkFramework()`) alike.

        /// The leaf certificate (index 0) plus any intermediates, as DER bytes. Built on
        /// `Internals.CertificateChain.resolvedDERBytes()` (portable, `SwiftASN1`-backed), which
        /// keeps this Darwin-only, `.urlSession`-reachable file free of any NIOSSL dependency. See
        /// `Internals.Certificate.resolvedDERBytes()`'s doc comment for the technique.
        package static func certificateDERs(from certificateChain: Internals.CertificateChain) throws -> [Data] {
            try certificateChain.resolvedDERBytes()
        }

        /// Loads the configured private key's raw bytes and, for `.pem`, strips the PEM armor
        /// down to DER, or, when a password is set, decrypts it first. Only traditional PKCS#1
        /// RSA PEM (`-----BEGIN RSA PRIVATE KEY-----` with `Proc-Type`/`DEK-Info` headers) can
        /// actually be decrypted here, via `_RSA.Signing.PrivateKey(encryptedPEMRepresentation:
        /// passphraseCallback:)`, the only encrypted-key entry point anywhere in this package's
        /// dependency graph. `swift-certificates` has none at all (its own private-key parsing
        /// only understands unencrypted PKCS#8 `PrivateKeyInfo`, for its own CSR/cert-signing
        /// needs).
        ///
        /// PKCS#8's `EncryptedPrivateKeyInfo` and every encrypted EC key (P-256/P-384/
        /// P-521, since `Crypto`'s own types have no passphrase-protected PEM import at all) still
        /// throw `Error/unsupportedKeyFormat(_:)`, same as a `.der`-sourced password-protected key:
        /// BoringSSL's own decryption call here only takes a PEM string, never raw DER.
        package static func privateKeyDER(from privateKeySource: Internals.PrivateKeySource) throws -> Data {
            switch privateKeySource {
            case .privateKey(let privateKey):
                let rawBytes: Data
                switch privateKey.source {
                case .bytes(let bytes):
                    rawBytes = Data(bytes)
                case .file(let file):
                    do {
                        rawBytes = try Data(contentsOf: URL(fileURLWithPath: file))
                    } catch {
                        throw SecureFileLoadError(resource: .privateKey, path: file, underlying: error)
                    }
                }

                if let password = privateKey.password {
                    guard privateKey.format == .pem else {
                        throw Error.unsupportedKeyFormat("password-protected key in DER format")
                    }
                    return try Self.decryptedRSAPrivateKeyDER(fromEncryptedPEM: rawBytes, password: password)
                }

                switch privateKey.format {
                case .der:
                    return rawBytes
                case .pem:
                    return try Self.privateKeyDER(fromPEM: rawBytes)
                }
            }
        }

        /// Decrypts a password-protected traditional PKCS#1 RSA PEM key via BoringSSL
        /// (`_RSA.Signing.PrivateKey(encryptedPEMRepresentation:passphraseCallback:)`, from
        /// `_CryptoExtras`) and returns its plain DER, ready for `secKey(fromDER:)`'s own
        /// PKCS#1/PKCS#8 cascade exactly like any other RSA key. Fails closed on anything that
        /// entry point can't parse: a wrong passphrase, an EC key, or a PKCS#8-encrypted one.
        private static func decryptedRSAPrivateKeyDER(
            fromEncryptedPEM pemData: Data,
            password: SecureBytes
        ) throws -> Data {
            guard let pemString = String(data: pemData, encoding: .utf8) else {
                throw Error.unsupportedKeyFormat("non-UTF8 input")
            }

            do {
                let key = try _RSA.Signing.PrivateKey(encryptedPEMRepresentation: pemString) { setPassphrase in
                    setPassphrase(Array(password))
                }
                return key.derRepresentation
            } catch {
                throw Error.unsupportedKeyFormat(
                    "password-protected key that isn't a decryptable traditional PKCS#1 RSA PEM key"
                )
            }
        }

        // MARK: - Certificate (DER bytes -> SecCertificate, no Keychain involved)

        package static func certificate(fromDER derBytes: Data) throws -> SecCertificate {
            guard let certificate = SecCertificateCreateWithData(nil, derBytes as CFData) else {
                throw Error.invalidCertificateData
            }
            return certificate
        }

        // MARK: - Private key (PEM -> DER)

        /// Strips PEM armor down to the DER payload of the first block that holds a private key,
        /// for any of the three labels this executor recognizes: PKCS#1 RSA (`RSA PRIVATE KEY`),
        /// SEC1 EC (`EC PRIVATE KEY`), and PKCS#8 (`PRIVATE KEY`, itself wrapping either RSA or
        /// EC). Which label matched doesn't change what happens next: ``secKey(fromDER:)``
        /// classifies the DER content itself, not the PEM label around it.
        ///
        /// Read with the same parser as the certificates, so a file with CRLF line endings, or one
        /// that also holds the certificate or other blocks, gives the same key as a file with only
        /// the key in it.
        package static func privateKeyDER(fromPEM pemData: Data) throws -> Data {
            guard let pemString = String(data: pemData, encoding: .utf8) else {
                throw Error.unsupportedKeyFormat("non-UTF8 input")
            }

            let documents: [PEMDocument]

            do {
                documents = try PEMDocument.parseMultiple(pemString: pemString)
            } catch {
                throw Error.unsupportedKeyFormat("malformed PEM")
            }

            let recognizedLabels: Set = ["RSA PRIVATE KEY", "EC PRIVATE KEY", "PRIVATE KEY"]

            guard let key = documents.first(where: { recognizedLabels.contains($0.discriminator) }) else {
                let header = documents.first.map { "-----BEGIN \($0.discriminator)-----" } ?? "empty input"
                throw Error.unsupportedKeyFormat(header)
            }

            return Data(key.derBytes)
        }

        // MARK: - Private key (DER -> SecKey)

        /// Builds a `SecKey` from DER-encoded private key bytes of unknown shape, trying each
        /// interpretation Security/CryptoKit can actually consume, in order:
        ///
        /// 1. Bare PKCS#1 (`RSAPrivateKey`): what `SecKeyCreateWithData` wants for RSA directly.
        /// 2. EC, either bare SEC1 (`ECPrivateKey`) or PKCS#8-wrapped. CryptoKit's DER
        ///    initializer accepts both shapes for whichever curve it is (P-256/P-384/P-521 tried
        ///    in that order, since nothing here is told the curve ahead of time), and its
        ///    `x963Representation` (`04 || X || Y || private scalar`) is what `SecKeyCreateWithData`
        ///    wants for EC. There is no direct entry point for SEC1/PKCS#8 DER the way there is
        ///    for RSA's PKCS#1.
        /// 3. PKCS#8-wrapped RSA: the one shape Security has no direct entry point for at all,
        ///    so the inner PKCS#1 payload is unwrapped by hand first.
        ///
        /// Anything else (Ed25519, X25519, malformed input, ...) is rejected.
        package static func secKey(fromDER der: Data) throws -> SecKey {
            if let key = Self.secKey(candidate: der, keyType: kSecAttrKeyTypeRSA, error: nil) {
                return key
            }

            if let x963 = ecX963Representation(fromDER: der) {
                var creationError: Unmanaged<CFError>?
                if let key = Self.secKey(
                    candidate: x963,
                    keyType: kSecAttrKeyTypeECSECPrimeRandom,
                    error: &creationError
                ) {
                    return key
                }
                // CryptoKit already parsed and validated this as a well-formed EC private key,
                // so a rejection of its own X9.63 output is a genuine Security-framework failure,
                // not a format-recognition miss.
                let message = creationError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                throw Error.secKeyCreationFailed(message)
            }

            if let unwrapped = try? pkcs1DER(fromPKCS8: der) {
                var creationError: Unmanaged<CFError>?
                if let key = Self.secKey(candidate: unwrapped, keyType: kSecAttrKeyTypeRSA, error: &creationError) {
                    return key
                }
                let message = creationError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                throw Error.secKeyCreationFailed(message)
            }

            throw Error.unsupportedKeyFormat(
                "not recognized as RSA (PKCS#1 or PKCS#8) or EC P-256/P-384/P-521 (SEC1 or PKCS#8)"
            )
        }

        private static func secKey(
            candidate data: Data,
            keyType: CFString,
            error: UnsafeMutablePointer<Unmanaged<CFError>?>?
        ) -> SecKey? {
            let attributes: [CFString: Any] = [
                kSecAttrKeyType: keyType,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            ]
            return SecKeyCreateWithData(data as CFData, attributes as CFDictionary, error)
        }

        /// Tries `der` as a bare SEC1 `ECPrivateKey` or a PKCS#8 envelope wrapping one, one curve
        /// size at a time. CryptoKit's DER initializer accepts both shapes for the same call, so
        /// there's no need to distinguish them here, and it derives the public point from the
        /// private scalar when SEC1's own (optional) public-key field is absent, which
        /// `SecKeyCreateWithData` has no way to do on its own.
        private static func ecX963Representation(fromDER der: Data) -> Data? {
            if let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
                return key.x963Representation
            }
            if let key = try? P384.Signing.PrivateKey(derRepresentation: der) {
                return key.x963Representation
            }
            if let key = try? P521.Signing.PrivateKey(derRepresentation: der) {
                return key.x963Representation
            }
            return nil
        }

        /// Unwraps PKCS#8's `PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE,
        /// privateKey OCTET STRING, ... }` down to its `privateKey` field. Doesn't check
        /// `algorithm`'s OID: the caller only keeps the result if it goes on to parse as PKCS#1
        /// RSA, so a PKCS#8-wrapped EC key (already handled by reading the *outer* PKCS#8 bytes
        /// directly in `ecX963Representation(fromDER:)`) or anything else simply fails that
        /// caller's own `SecKeyCreateWithData` check instead of being misidentified here.
        private static func pkcs1DER(fromPKCS8 der: Data) throws -> Data {
            var reader = DERReader(Array(der))
            var envelope = DERReader(try reader.readSequence())
            _ = try envelope.read(tag: 0x02)  // version INTEGER, value unused
            _ = try envelope.readSequence()  // algorithm identifier, OID unused (see doc comment)
            return Data(try envelope.read(tag: 0x04))  // privateKey OCTET STRING
        }

        // MARK: - Identity (bytes -> SecIdentity, in memory)

        /// Builds a `SecIdentity` from a DER-encoded certificate and a private key of any format
        /// ``secKey(fromDER:)`` recognizes, entirely in memory: nothing is written to, read from or
        /// deleted from any Keychain.
        ///
        /// `SecIdentityCreate` pairs the two objects directly and is public on every platform this
        /// package supports (macOS 10.12, iOS 11.2, tvOS 11.2, watchOS 4.2, visionOS 1.0). It
        /// returns `nil` when the key is not the certificate's, which is what
        /// ``Error/privateKeyDoesNotMatchCertificate`` reports.
        ///
        /// Because no item is stored, no process can delete what another one still uses, and the
        /// identity needs neither the Keychain Sharing entitlement nor a signed app. The private
        /// key lives as long as the returned handle (and whatever `URLSession` or
        /// Network.framework retained of the identity) holds it.
        package static func makeIdentity(
            certificateDER: Data,
            privateKeyDER: Data
        ) throws -> Internals.IdentityHandle {
            try makeIdentity(
                certificateDER: certificateDER,
                privateKeyDER: privateKeyDER,
                afterBuilding: Internals.LegacyIdentityItems.scheduleOnce
            )
        }

        /// - Parameter afterBuilding: Runs once the identity is built, never when it is not, and
        ///   cannot change what is returned: it is what starts the cleanup of the keys earlier
        ///   versions left in the Keychain (see ``Internals/LegacyIdentityItems``), best effort and
        ///   off this thread, once per process.
        package static func makeIdentity(
            certificateDER: Data,
            privateKeyDER: Data,
            afterBuilding: () -> Void
        ) throws -> Internals.IdentityHandle {
            let certificate = try certificate(fromDER: certificateDER)
            let secKey = try Self.secKey(fromDER: privateKeyDER)

            // Checked on public-key bytes first, and never skipped: `SecIdentityCreate` aborts the
            // process on a certificate whose public key cannot be read (see
            // `validate(certificatePublicKey:pairsWith:)`), and its answer for a pair that does
            // not match is not something every OS release is known to give (`nil` is what it
            // gives on the ones this was checked against, and still maps to the same error below).
            try Self.validate(certificate: certificate, pairsWith: try Self.applicationLabel(of: secKey))

            guard let identity = SecIdentityCreate(nil, certificate, secKey) else {
                throw Error.privateKeyDoesNotMatchCertificate
            }

            let handle = Internals.IdentityHandle(identity: identity)

            afterBuilding()

            return handle
        }

        // MARK: - Public key pairing

        /// SHA-1 of the public key's external representation (X9.63 for EC, PKCS#1
        /// `RSAPublicKey` for RSA; `SecKeyCopyExternalRepresentation` already returns whichever
        /// shape matches the key's own type): the OS's own convention for a key's
        /// `kSecAttrApplicationLabel`, confirmed byte for byte against `openssl`'s equivalent
        /// computation. Two encodings of one private key give the same value.
        package static func applicationLabel(of secKey: SecKey) throws -> Data {
            guard let publicKey = SecKeyCopyPublicKey(secKey) else {
                throw Error.secKeyCreationFailed("SecKeyCopyPublicKey returned nil")
            }

            var error: Unmanaged<CFError>?
            guard let representation = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
                let message = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                throw Error.secKeyCreationFailed("SecKeyCopyExternalRepresentation failed: \(message)")
            }

            return Data(Insecure.SHA1.hash(data: representation))
        }

        /// Throws when `certificate`'s public key is not the one `applicationLabel` is the hash
        /// of.
        private static func validate(certificate: SecCertificate, pairsWith applicationLabel: Data) throws {
            let representation = SecCertificateCopyKey(certificate).flatMap {
                SecKeyCopyExternalRepresentation($0, nil) as Data?
            }

            try validate(certificatePublicKey: representation, pairsWith: applicationLabel)
        }

        /// - Parameter certificatePublicKey: The external representation of the certificate's
        ///   public key, or `nil` when it cannot be read back. Throws then, and never reaches
        ///   `SecIdentityCreate`: handed such a certificate it raises an Objective-C exception
        ///   (`SecKeyCopyExternalRepresentation called with NULL SecKeyRef`) that nothing can
        ///   catch, and the process aborts.
        package static func validate(certificatePublicKey: Data?, pairsWith applicationLabel: Data) throws {
            guard let certificatePublicKey else {
                throw Error.unsupportedCertificatePublicKey
            }

            guard Data(Insecure.SHA1.hash(data: certificatePublicKey)) == applicationLabel else {
                throw Error.privateKeyDoesNotMatchCertificate
            }
        }

    }
}

/// Minimal DER TLV (tag-length-value) reader, only as much as unwrapping a PKCS#8
/// `PrivateKeyInfo` envelope needs, not a general-purpose ASN.1 parser. Bounds-checked
/// throughout: malformed input throws rather than trapping.
private struct DERReader {

    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Reads one TLV whose tag must be `0x30` (SEQUENCE) and returns its content bytes.
    mutating func readSequence() throws -> [UInt8] {
        try read(tag: 0x30)
    }

    /// Reads one TLV whose tag must match `tag` and returns its content bytes. Supports both
    /// short-form and long-form DER lengths, since PKCS#8 envelopes routinely exceed the
    /// 127-byte short-form limit once a real RSA key is inside.
    mutating func read(tag: UInt8) throws -> [UInt8] {
        guard offset < bytes.count, bytes[offset] == tag else {
            throw MalformedDERError()
        }
        offset += 1

        guard offset < bytes.count else { throw MalformedDERError() }
        var length = Int(bytes[offset])
        offset += 1

        if length & 0x80 != 0 {
            let lengthByteCount = length & 0x7F
            guard lengthByteCount > 0, lengthByteCount <= 4, offset + lengthByteCount <= bytes.count else {
                throw MalformedDERError()
            }

            // Accumulated in `UInt64`: four bytes can reach `0xFFFF_FFFF`, which `Int` cannot hold
            // where it is 32 bits (watchOS arm64_32), and shifting into the sign bit would turn
            // a malformed length into a negative one that slips past the bounds check below.
            var wideLength: UInt64 = 0
            for _ in 0..<lengthByteCount {
                wideLength = (wideLength << 8) | UInt64(bytes[offset])
                offset += 1
            }

            // Not clamped: a length that does not fit is a malformed envelope, and clamping it
            // would only hide that behind a confusing failure further down.
            guard let exactLength = Int(exactly: wideLength) else {
                throw MalformedDERError()
            }
            length = exactLength
        }

        // Compared by subtraction: `offset + length` could overflow a 32-bit `Int`.
        guard length <= bytes.count - offset else { throw MalformedDERError() }
        defer { offset += length }
        return Array(bytes[offset..<(offset + length)])
    }
}

private struct MalformedDERError: Swift.Error {}

#endif
