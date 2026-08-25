//
// See LICENSE for this package's licensing information.
//

// Promoted from the URLSession Executor Spike (formerly
// `Tests/RequestDLTests/URLSession Executor Spike/RawBytesIdentityBuilder.swift`) for
// request-dl-nio#287. RSA/PKCS#1 only for this first cut, matching what the spike validated;
// PKCS#8 and EC key support are not yet implemented.

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
                case .unsupportedKeyFormat(let header):
                    return """
                        Unsupported private key format (\(header)). Only RSA/PKCS#1 \
                        ("-----BEGIN RSA PRIVATE KEY-----") is supported for mTLS under the \
                        URLSession executor today.
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

        // MARK: - Private key (PEM -> raw PKCS#1 DER)

        /// Extracts the raw PKCS#1 DER payload from an RSA private key PEM
        /// (`-----BEGIN RSA PRIVATE KEY-----`) -- the only format promoted for this first cut.
        package static func rsaPKCS1DER(fromPEM pemData: Data) throws -> Data {
            guard let pemString = String(data: pemData, encoding: .utf8) else {
                throw Error.unsupportedKeyFormat("non-UTF8 input")
            }

            guard pemString.contains("-----BEGIN RSA PRIVATE KEY-----") else {
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

        // MARK: - Identity (bytes -> SecIdentity, via a Keychain round-trip)

        /// Builds a `SecIdentity` from a DER-encoded certificate and a raw PKCS#1 RSA private key.
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

            var keyCreationError: Unmanaged<CFError>?
            let keyAttributes: [CFString: Any] = [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            ]

            guard
                let secKey = SecKeyCreateWithData(
                    privateKeyDER as CFData,
                    keyAttributes as CFDictionary,
                    &keyCreationError
                )
            else {
                let message = keyCreationError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
                throw Error.secKeyCreationFailed(message)
            }

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

#endif
