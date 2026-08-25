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
/// Building that identity is a Keychain round-trip with no in-memory alternative on Apple
/// platforms -- see <doc:Using-a-Client-Certificate-with-URLSession> for the full walkthrough,
/// including the one-time Xcode project setting
/// (``Reason/missingKeychainSharingEntitlement(operation:)``'s most common cause) most apps using
/// ``Certificate``/``PrivateKey`` under this executor need.
///
/// `RequestDLInternals`'s raw `Internals.RawBytesIdentityBuilder.Error`/
/// `Internals.URLSessionIdentityPolicy.ConfigurationError` -- the internal, package-visible errors
/// -- get caught where the session bootstraps and rewrapped into this type, following the same
/// split `SecureFileError` uses for `Internals.SecureFileLoadError`.
public struct ClientIdentityError: Error, Sendable {

    /// The specific reason RequestDL could not build a `URLSession`-presentable identity.
    public enum Reason: Sendable {
        /// `SecureConnection` configured only a `certificateChain` or only a `privateKey` -- mTLS
        /// under `.urlSession` needs both.
        case incompleteClientIdentity

        /// `certificateChain` was configured but resolved to zero certificates.
        case emptyCertificateChain

        /// The configured certificate bytes could not be parsed as a certificate at all.
        case invalidCertificateData

        /// The configured private key isn't in a format this executor supports yet. `header` is
        /// the first line of what was actually supplied, to help spot the mismatch (e.g. a
        /// PKCS#8 `"-----BEGIN PRIVATE KEY-----"` key, not yet supported).
        case unsupportedKeyFormat(header: String)

        /// The Security framework rejected the private key bytes outright while building a
        /// `SecKey` from them. `message` is the underlying `CFError` description.
        case keyCreationFailed(message: String)

        /// This app is missing the Keychain Sharing capability that writing a client
        /// certificate/private key into the Keychain requires. `operation` names the specific
        /// Keychain call that failed. This is almost always fixed by adding **Keychain Sharing**
        /// under the affected target's Signing & Capabilities tab in Xcode -- see
        /// <doc:Using-a-Client-Certificate-with-URLSession>.
        case missingKeychainSharingEntitlement(operation: String)

        /// A Keychain operation failed for a reason other than a missing entitlement. `operation`
        /// names the specific Keychain call, `status` is the underlying `OSStatus`.
        ///
        /// On a non-sandboxed macOS process (a bare command-line tool, for instance), this can
        /// surface even with Keychain Sharing correctly configured -- see
        /// <doc:Using-a-Client-Certificate-with-URLSession>'s "Platforms" section for that
        /// specific, still-unresolved gap -- adding Keychain Sharing again will not fix it.
        case keychainOperationFailed(operation: String, status: OSStatus)

        /// An internal Keychain query returned a value of an unexpected type. Not expected to
        /// happen in practice; please report this if it does.
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
            case .missingKeychainSharingEntitlement(let operation):
                self = .missingKeychainSharingEntitlement(operation: operation)
            case .keychainOperationFailed(let status, let operation):
                self = .keychainOperationFailed(operation: operation, status: status)
            case .identityLookupReturnedWrongType:
                self = .identityLookupReturnedWrongType
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

    /// Rewraps the raw Keychain-failure `Internals.RawBytesIdentityBuilder` throws from
    /// `RequestDLInternals`, where the public, documented ``ClientIdentityError`` itself isn't
    /// reachable.
    init(_ error: Internals.RawBytesIdentityBuilder.Error) {
        self.reason = Reason(error)
    }
}

// MARK: - LocalizedError

extension ClientIdentityError: LocalizedError {

    /// A message describing what went wrong, self-diagnosable without needing to have already
    /// read <doc:Using-a-Client-Certificate-with-URLSession> -- this is what
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
                the configured private key isn't in a supported format (found: "\(header)"). Only \
                RSA/PKCS#1 ("-----BEGIN RSA PRIVATE KEY-----") is supported for mTLS under the \
                URLSession executor today.
                """
        case .keyCreationFailed(let message):
            return "the configured private key was rejected: \(message)."
        case .missingKeychainSharingEntitlement(let operation):
            return """
                \(operation) failed because this app is missing the Keychain Sharing capability \
                mTLS under the URLSession executor needs, in order to store a client certificate/\
                private key. In Xcode, select this target's Signing & Capabilities tab, click "+ \
                Capability", and add "Keychain Sharing" -- no further configuration is needed. See \
                https://github.com/request-dl/request-dl-nio/blob/main/Sources/RequestDL/Documentation.docc/Advanced/Using-a-Client-Certificate-with-URLSession.md#troubleshooting \
                for the full walkthrough.
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
