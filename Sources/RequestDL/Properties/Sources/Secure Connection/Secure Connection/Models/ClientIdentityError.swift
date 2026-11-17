//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import protocol Foundation.LocalizedError
#endif

/// An error thrown when RequestDL cannot turn a configured client certificate/private key into a
/// `URLSession`-presentable identity, under the `.urlSession` executor (`Session.Executor`).
///
/// The identity is built in memory from the certificate and the private key: nothing is written to
/// the Keychain, and no Keychain Sharing entitlement or signed app is needed. See
/// <doc:Using-a-Client-Certificate-with-URLSession> for the walkthrough.
///
/// ``Reason/missingKeychainSharingEntitlement(operation:)``,
/// ``Reason/keychainOperationFailed(operation:status:)`` and
/// ``Reason/identityLookupReturnedWrongType`` were thrown by versions that stored the identity in
/// the Keychain. They are deprecated: they are kept so existing code that switches over ``Reason``
/// keeps compiling, but nothing throws them any more, and a `switch` can drop them.
///
/// `RequestDLInternals`'s raw `Internals.RawBytesIdentityBuilder.Error`/
/// `Internals.URLSessionIdentityPolicy.ConfigurationError` (the internal, package-visible errors)
/// get caught where the session bootstraps and rewrapped into this type, following the same
/// split `SecureFileError` uses for `Internals.SecureFileLoadError`.
public struct ClientIdentityError: Error, Sendable {

    /// The specific reason RequestDL could not build a `URLSession`-presentable identity.
    public enum Reason: Sendable {
        /// `SecureConnection` configured only a `certificateChain` or only a `privateKey`; mTLS
        /// under `.urlSession` needs both.
        case incompleteClientIdentity

        /// `certificateChain` was configured but resolved to zero certificates.
        case emptyCertificateChain

        /// The configured certificate bytes could not be parsed as a certificate at all.
        case invalidCertificateData

        /// The configured private key isn't RSA (PKCS#1 or PKCS#8) or EC P-256/P-384/P-521 (SEC1
        /// or PKCS#8), the shapes this executor recognizes. `header` describes what was
        /// actually supplied, to help spot the mismatch (e.g. an Ed25519 key, which has no
        /// `SecKeyCreateWithData` entry point at all).
        case unsupportedKeyFormat(header: String)

        /// The Security framework rejected the private key bytes outright while building a
        /// `SecKey` from them. `message` is the underlying `CFError` description.
        case keyCreationFailed(message: String)

        /// No longer thrown, and deprecated. Older versions stored the client certificate and
        /// private key in the Keychain, which needed the Keychain Sharing capability; the identity
        /// is now built in memory and needs no capability. Kept only so existing `switch`
        /// statements over ``Reason`` keep compiling.
        @available(
            *,
            deprecated,
            message:
                "The client identity is now built in memory and never stored in the Keychain, so this is never thrown. Remove it from your switch."
        )
        case missingKeychainSharingEntitlement(operation: String)

        /// No longer thrown, and deprecated. Older versions reported here a failed Keychain call
        /// (`operation` names it, `status` is the `OSStatus`); nothing is stored in the Keychain
        /// any more. Kept only so existing `switch` statements over ``Reason`` keep compiling.
        @available(
            *,
            deprecated,
            message:
                "The client identity is now built in memory and never stored in the Keychain, so this is never thrown. Remove it from your switch."
        )
        case keychainOperationFailed(operation: String, status: OSStatus)

        /// No longer thrown, and deprecated. Older versions reported here an unexpected result of
        /// an internal Keychain query; no such query is made any more. Kept only so existing
        /// `switch` statements over ``Reason`` keep compiling.
        @available(
            *,
            deprecated,
            message:
                "The client identity is now built in memory and never queried from the Keychain, so this is never thrown. Remove it from your switch."
        )
        case identityLookupReturnedWrongType

        // MARK: - Inits

        init(_ error: Internals.URLSessionIdentityPolicy.ConfigurationError) {
            switch error {
            case .incompleteClientIdentity:
                self = .incompleteClientIdentity
            case .emptyCertificateChain:
                self = .emptyCertificateChain
            }
        }

        init(_ error: Internals.RawBytesIdentityBuilder.Error) {
            switch error {
            case .invalidCertificateData:
                self = .invalidCertificateData
            case .unsupportedKeyFormat(let header):
                self = .unsupportedKeyFormat(header: header)
            case .secKeyCreationFailed(let message):
                self = .keyCreationFailed(message: message)
            case .privateKeyDoesNotMatchCertificate:
                self = .keyCreationFailed(message: "it is not the private key of the configured certificate")
            case .unsupportedCertificatePublicKey:
                self = .keyCreationFailed(
                    message: "the public key of the configured certificate uses an unsupported algorithm or curve"
                )
            }
        }
    }

    // MARK: - Public properties

    /// The specific reason RequestDL could not build a `URLSession`-presentable identity.
    public let reason: Reason

    // MARK: - Inits

    /// Rewraps the raw configuration-failure `Internals.URLSessionIdentityPolicy` throws from
    /// `RequestDLInternals`, where the public, documented ``ClientIdentityError`` itself isn't
    /// reachable.
    init(_ error: Internals.URLSessionIdentityPolicy.ConfigurationError) {
        self.reason = Reason(error)
    }

    /// Rewraps the raw failure `Internals.RawBytesIdentityBuilder` throws from
    /// `RequestDLInternals`, where the public, documented ``ClientIdentityError`` itself isn't
    /// reachable.
    init(_ error: Internals.RawBytesIdentityBuilder.Error) {
        self.reason = Reason(error)
    }
}

// MARK: - LocalizedError

extension ClientIdentityError: LocalizedError {

    /// A message describing what went wrong, self-diagnosable without needing to have already
    /// read <doc:Using-a-Client-Certificate-with-URLSession>. This is what
    /// `error.localizedDescription` surfaces, the way most callers actually display a caught
    /// error.
    public var errorDescription: String? {
        description
    }
}

// MARK: - CustomStringConvertible

extension ClientIdentityError: CustomStringConvertible {

    public var description: String {
        "RequestDL could not build a client identity for the .urlSession executor: \(reason.description)"
    }
}

// MARK: - Reason.CustomStringConvertible

extension ClientIdentityError.Reason: CustomStringConvertible {

    public var description: String {
        switch self {
        case .incompleteClientIdentity:
            return
                "mTLS under the URLSession executor needs both a certificateChain and a privateKey configured on SecureConnection; only one was."
        case .emptyCertificateChain:
            return "certificateChain was configured but resolved to zero certificates."
        case .invalidCertificateData:
            return "the configured certificate data could not be parsed as a certificate."
        case .unsupportedKeyFormat(let header):
            return """
                the configured private key isn't in a supported format (found: "\(header)"). RSA \
                (PKCS#1 or PKCS#8) and EC P-256/P-384/P-521 (SEC1 or PKCS#8) are supported for \
                mTLS under the URLSession executor.
                """
        case .keyCreationFailed(let message):
            return "the configured private key was rejected: \(message)."
        case .missingKeychainSharingEntitlement(let operation):
            return """
                \(operation) failed because this app is missing the Keychain Sharing capability. \
                This is no longer thrown: the client identity is built in memory and needs no \
                capability.
                """
        case .keychainOperationFailed(let operation, let status):
            let message = SecCopyErrorMessageString(status, nil).map { String($0) } ?? "unknown"
            return "\(operation) failed with OSStatus \(status) (\(message))."
        case .identityLookupReturnedWrongType:
            return "an internal Keychain query returned an unexpected type; please report this."
        }
    }
}

#endif
