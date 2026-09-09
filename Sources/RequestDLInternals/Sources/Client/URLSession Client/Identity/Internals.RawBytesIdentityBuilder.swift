//
// See LICENSE for this package's licensing information.
//

// Promoted from the URLSession Executor Spike (formerly
// `Tests/RequestDLTests/URLSession Executor Spike/RawBytesIdentityBuilder.swift`) for
// request-dl-nio#287. Supports RSA (PKCS#1 or PKCS#8) and EC P-256/P-384/P-521 (SEC1 or
// PKCS#8) private keys.

#if canImport(Darwin)

import CryptoKit
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    /// Builds a `SecIdentity` (a `URLSession`-presentable client certificate) from raw
    /// certificate + private key bytes, via the only public path available on Apple platforms: a
    /// Keychain round-trip. See `Internals.URLSessionIdentityPolicy` for how this turns an
    /// `Internals.SecureConnection` into per-host TLS challenge handling.
    package enum RawBytesIdentityBuilder {

        package enum Error: Swift.Error, CustomStringConvertible, Sendable {
            case invalidCertificateData
            case unsupportedKeyFormat(String)
            case secKeyCreationFailed(String)
            case keychainOperationFailed(OSStatus, operation: String)
            case missingKeychainSharingEntitlement(operation: String)
            case identityLookupReturnedWrongType

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
                        "-----BEGIN PRIVATE KEY-----").
                        """
                case .secKeyCreationFailed(let message):
                    return "SecKeyCreateWithData failed: \(message)."
                case .keychainOperationFailed(let status, let operation):
                    let message = SecCopyErrorMessageString(status, nil).map { String($0) } ?? "unknown"
                    return "\(operation) failed with OSStatus \(status) (\(message))."
                case .missingKeychainSharingEntitlement(let operation):
                    return """
                        \(operation) failed because this app is missing the Keychain Sharing \
                        capability mTLS under the URLSession executor needs in order to store a \
                        client certificate/private key. In Xcode, select this target's Signing & \
                        Capabilities tab, click "+ Capability", and add "Keychain Sharing" -- no \
                        further configuration is needed. See \
                        https://github.com/request-dl/request-dl-nio/blob/main/Sources/RequestDL/Documentation.docc/Advanced/Using-a-Client-Certificate-with-URLSession.md \
                        for the full walkthrough.
                        """
                case .identityLookupReturnedWrongType:
                    return "SecItemCopyMatching(kSecClassIdentity) returned an unexpected type."
                }
            }
        }

        /// One identity built by ``makeIdentity(certificateDER:privateKeyDER:)``, together with
        /// everything needed to remove it from the Keychain again.
        package struct Handle {
            package let identity: SecIdentity
            fileprivate let label: String
        }

        // MARK: - Certificate (DER bytes -> SecCertificate, no Keychain involved)

        package static func certificate(fromDER derBytes: Data) throws -> SecCertificate {
            guard let certificate = SecCertificateCreateWithData(nil, derBytes as CFData) else {
                throw Error.invalidCertificateData
            }
            return certificate
        }

        // MARK: - Private key (PEM -> DER)

        /// Strips PEM armor down to the base64-decoded DER payload, for any of the three headers
        /// this executor recognizes for a private key: PKCS#1 RSA (`RSA PRIVATE KEY`), SEC1 EC
        /// (`EC PRIVATE KEY`), and PKCS#8 (`PRIVATE KEY`, itself wrapping either RSA or EC). Which
        /// header matched doesn't change what happens next -- ``secKey(fromDER:)`` classifies the
        /// DER content itself, not the PEM label around it.
        package static func privateKeyDER(fromPEM pemData: Data) throws -> Data {
            guard let pemString = String(data: pemData, encoding: .utf8) else {
                throw Error.unsupportedKeyFormat("non-UTF8 input")
            }

            let recognizedHeaders = [
                "-----BEGIN RSA PRIVATE KEY-----",
                "-----BEGIN EC PRIVATE KEY-----",
                "-----BEGIN PRIVATE KEY-----",
            ]

            guard recognizedHeaders.contains(where: pemString.contains) else {
                let header = pemString.split(separator: "\n").first.map(String.init) ?? "empty input"
                throw Error.unsupportedKeyFormat(header)
            }

            let base64 =
                pemString
                .split(separator: "\n")
                .filter { !$0.hasPrefix("-----") }
                .joined()

            guard let der = Data(base64Encoded: base64) else {
                throw Error.unsupportedKeyFormat("malformed base64 body")
            }

            return der
        }

        // MARK: - Private key (DER -> SecKey)

        /// Builds a `SecKey` from DER-encoded private key bytes of unknown shape, trying each
        /// interpretation Security/CryptoKit can actually consume, in order:
        ///
        /// 1. Bare PKCS#1 (`RSAPrivateKey`) -- what `SecKeyCreateWithData` wants for RSA directly.
        /// 2. EC, either bare SEC1 (`ECPrivateKey`) or PKCS#8-wrapped -- CryptoKit's DER
        ///    initializer accepts both shapes for whichever curve it is (P-256/P-384/P-521 tried
        ///    in that order, since nothing here is told the curve ahead of time), and its
        ///    `x963Representation` (`04 || X || Y || private scalar`) is what `SecKeyCreateWithData`
        ///    wants for EC -- there is no direct entry point for SEC1/PKCS#8 DER the way there is
        ///    for RSA's PKCS#1.
        /// 3. PKCS#8-wrapped RSA -- the one shape Security has no direct entry point for at all,
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
                // CryptoKit already parsed and validated this as a well-formed EC private key --
                // a rejection of its own X9.63 output is a genuine Security-framework failure,
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
        /// size at a time -- CryptoKit's DER initializer accepts both shapes for the same call, so
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
        /// `algorithm`'s OID -- the caller only keeps the result if it goes on to parse as PKCS#1
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

        // MARK: - Identity (bytes -> SecIdentity, via a Keychain round-trip)

        /// Builds a `SecIdentity` from a DER-encoded certificate and a private key of any format
        /// ``secKey(fromDER:)`` recognizes.
        ///
        /// There is no public API on iOS to pair a certificate and a private key into a
        /// `SecIdentity` purely in memory (`SecIdentityCreateWithCertificate` is macOS-only). The
        /// only public path is a Keychain round-trip: add both items, then query them back
        /// together as a single `kSecClassIdentity` match -- which is exactly what this does,
        /// deliberately avoiding the macOS-only shortcut so the result generalizes to iOS/tvOS/
        /// watchOS.
        package static func makeIdentity(
            certificateDER: Data,
            privateKeyDER: Data
        ) throws -> Handle {
            let certificate = try certificate(fromDER: certificateDER)
            let secKey = try Self.secKey(fromDER: privateKeyDER)

            // Deterministic (content-derived, not random) so that rebuilding an identity for the
            // same certificate -- a repeated test run, or an app relaunching with the same
            // configured client certificate after a previous run's `deinit`-triggered `remove(_:)`
            // never got to run -- reliably finds and clears its own leftovers below instead of
            // hitting errSecDuplicateItem. `kSecValueRef`-based matching (delete "whatever item
            // has this exact key/certificate value") looked like the more direct way to express
            // that and is what the original spike did, but empirically did not reliably match an
            // existing item across process runs; label-based matching does.
            let label = "RequestDL.mtls." + Self.hexDigest(certificateDER)

            // `swift test` (and any unsigned command-line process) has no `keychain-access-groups`
            // entitlement, which the data-protection keychain requires -- forcing the legacy
            // file-based keychain is a macOS-only accommodation for that. Not present on
            // iOS/tvOS/watchOS, where there is only the data-protection keychain and a properly
            // signed/provisioned app already carries the entitlement it needs.
            #if os(macOS)
            let useDataProtectionKeychain = false
            #else
            let useDataProtectionKeychain = true
            #endif

            SecItemDelete(
                [
                    kSecClass: kSecClassKey,
                    kSecAttrLabel: label,
                    kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                ] as CFDictionary
            )
            SecItemDelete(
                [
                    kSecClass: kSecClassCertificate,
                    kSecAttrLabel: label,
                    kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                ] as CFDictionary
            )

            try addToKeychain(
                query: [
                    kSecClass: kSecClassKey,
                    kSecValueRef: secKey,
                    kSecAttrLabel: label,
                    // This device only, not iCloud Keychain -- the key only needs to survive this
                    // process's lifetime, not sync anywhere.
                    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                ],
                operation: "SecItemAdd(key)"
            )

            try addToKeychain(
                query: [
                    kSecClass: kSecClassCertificate,
                    kSecValueRef: certificate,
                    kSecAttrLabel: label,
                    kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                ],
                operation: "SecItemAdd(certificate)"
            )

            // `kSecClassIdentity` queries do not reliably honor `kSecAttrLabel` as a filter -- an
            // identity is a synthetic pairing of a certificate and a key by matching public key,
            // not an item with its own attributes, so the label set on the certificate/key above
            // isn't necessarily inherited by it. Fetching every identity currently in this
            // keychain and matching by certificate bytes is the approach that reliably works in
            // practice.
            let identityQuery: [CFString: Any] = [
                kSecClass: kSecClassIdentity,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecReturnRef: true,
                kSecUseDataProtectionKeychain: useDataProtectionKeychain,
            ]

            var identitiesResult: CFTypeRef?
            let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identitiesResult)

            guard identityStatus == errSecSuccess else {
                throw Error.keychainOperationFailed(identityStatus, operation: "SecItemCopyMatching(identity)")
            }

            guard let identities = identitiesResult as? [SecIdentity] else {
                throw Error.identityLookupReturnedWrongType
            }

            let wantedCertificateData = SecCertificateCopyData(certificate) as Data

            let matchingIdentity = identities.first { identity in
                var identityCertificate: SecCertificate?
                guard
                    SecIdentityCopyCertificate(identity, &identityCertificate) == errSecSuccess,
                    let identityCertificate
                else {
                    return false
                }

                return (SecCertificateCopyData(identityCertificate) as Data) == wantedCertificateData
            }

            guard let matchingIdentity else {
                throw Error.keychainOperationFailed(errSecItemNotFound, operation: "matching identity by certificate")
            }

            return Handle(identity: matchingIdentity, label: label)
        }

        /// Removes both Keychain items an identity built by
        /// ``makeIdentity(certificateDER:privateKeyDER:)`` was built from.
        /// `Internals.URLSessionIdentityPolicy` calls this from `deinit`, once the identity is no
        /// longer needed -- not after every request.
        package static func remove(_ handle: Handle) {
            #if os(macOS)
            let useDataProtectionKeychain = false
            #else
            let useDataProtectionKeychain = true
            #endif

            for itemClass in [kSecClassKey, kSecClassCertificate] {
                let query: [CFString: Any] = [
                    kSecClass: itemClass,
                    kSecAttrLabel: handle.label,
                    kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                ]
                SecItemDelete(query as CFDictionary)
            }
        }

        // MARK: - Private methods

        private static func addToKeychain(query: [CFString: Any], operation: String) throws {
            var result: CFTypeRef?
            let status = SecItemAdd(query as CFDictionary, &result)

            guard status == errSecSuccess else {
                // The label-based delete right above this call is best-effort, not a guarantee --
                // e.g. a previous process that never reached its own `remove(_:)` (killed rather
                // than cleanly terminated). An item already present with this exact label means
                // this exact certificate/key is already stored (Keychain's own duplicate-item
                // constraint for these classes is content-derived: issuer+serial for
                // certificates, key material for keys), which is exactly the state this call was
                // trying to reach -- so this is success, not failure.
                if status == errSecDuplicateItem {
                    return
                }
                if status == errSecMissingEntitlement {
                    throw Error.missingKeychainSharingEntitlement(operation: operation)
                }
                throw Error.keychainOperationFailed(status, operation: operation)
            }
        }

        /// Lowercase hex SHA-256 of `data` -- deterministic Keychain item labeling only, not a
        /// security boundary, so `CryptoKit` (always available on Darwin) is enough; no need for
        /// a constant-time comparison anywhere this is used.
        private static func hexDigest(_ data: Data) -> String {
            SHA256.hash(data: data).map {
                let hex = String($0, radix: 16)
                return hex.count == 1 ? "0" + hex : hex
            }.joined()
        }
    }
}

/// Minimal DER TLV (tag-length-value) reader -- only as much as unwrapping a PKCS#8
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
    /// short-form and long-form DER lengths -- PKCS#8 envelopes routinely exceed the 127-byte
    /// short-form limit once a real RSA key is inside.
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
            length = 0
            for _ in 0..<lengthByteCount {
                length = (length << 8) | Int(bytes[offset])
                offset += 1
            }
        }

        guard offset + length <= bytes.count else { throw MalformedDERError() }
        defer { offset += length }
        return Array(bytes[offset..<(offset + length)])
    }
}

private struct MalformedDERError: Swift.Error {}

#endif
