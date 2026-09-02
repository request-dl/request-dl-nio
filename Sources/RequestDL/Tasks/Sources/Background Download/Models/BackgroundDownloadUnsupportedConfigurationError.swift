//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import protocol Foundation.LocalizedError
#endif

/// An error thrown when a ``BackgroundDownloadTask``'s content configures a client certificate
/// (mTLS) or SPKI pinning in a shape that can't survive a relaunch.
///
/// A background download can outlive the process that started it -- the delegate answering a
/// challenge after the app relaunches has no `Property` tree left to resolve
/// `certificateChain`/`privateKey`/``SPKIPinning`` from, only whatever was persisted alongside
/// `id`/`destination` on the scheduled task itself. `Certificate`/`PrivateKey` backed by a
/// **file path** work fine: the path is what's persisted, and the identity is rebuilt from that
/// file via the same Keychain round-trip on every challenge, live or after a relaunch alike. What
/// doesn't survive is anything that isn't a stable path on disk, or an SPKI pin hashed with
/// something other than SHA-256/384/512 -- see ``Reason`` for the specific cases.
///
/// `TrustRoots`/`AdditionalTrustRoots`/``SecureConnection/verification(_:)`` are unaffected by any
/// of this: their certificate bytes are public, so they're persisted directly rather than by
/// path, and work regardless of how they were originally configured.
public struct BackgroundDownloadUnsupportedConfigurationError: Error, Sendable {

    /// The specific reason a client certificate or SPKI pinning configuration can't be used in a
    /// background download.
    public enum Reason: Sendable {
        /// Only one of `certificateChain`/`privateKey` was configured -- mTLS needs both.
        case incompleteClientIdentity

        /// `certificateChain` or `privateKey` came from in-memory bytes or a pre-built
        /// certificate, not a file path. Only a file path is guaranteed to still be there to
        /// re-read after a relaunch -- in-memory bytes are gone with the process that held them.
        case nonFileBackedSource

        /// The private key is password-protected. Decrypting it once and persisting the
        /// decrypted bytes would defeat the point of the password; persisting the password
        /// itself would mean storing a secret in the task's own state. Neither is done.
        case passwordProtectedPrivateKey

        /// ``SPKIPinning`` was configured with an ``SPKIHash`` whose hash algorithm isn't
        /// SHA-256, SHA-384, or SHA-512. Those three are the only algorithms a relaunched process
        /// can recompute against a peer's certificate on its own; anything else only ever existed
        /// as a `Crypto.HashFunction` closure in the process that configured it, which is gone
        /// once that process exits.
        case spkiPinningAlgorithmNotSupported

        // MARK: - Inits

        init(_ reason: Internals.ClientIdentityDescriptor.ResolutionError) {
            switch reason {
            case .incompleteClientIdentity:
                self = .incompleteClientIdentity
            case .nonFileBackedSource:
                self = .nonFileBackedSource
            case .passwordProtectedPrivateKey:
                self = .passwordProtectedPrivateKey
            }
        }

        init(_ reason: Internals.ServerTrustPolicy.DescriptorError) {
            switch reason {
            case .unpersistableAlgorithm:
                self = .spkiPinningAlgorithmNotSupported
            }
        }
    }

    // MARK: - Public properties

    public let reason: Reason

    // MARK: - Inits

    init(_ reason: Internals.ClientIdentityDescriptor.ResolutionError) {
        self.reason = Reason(reason)
    }

    init(_ reason: Internals.ServerTrustPolicy.DescriptorError) {
        self.reason = Reason(reason)
    }
}

// MARK: - LocalizedError

extension BackgroundDownloadUnsupportedConfigurationError: LocalizedError {

    public var errorDescription: String? {
        description
    }
}

// MARK: - CustomStringConvertible

extension BackgroundDownloadUnsupportedConfigurationError: CustomStringConvertible {

    public var description: String {
        "BackgroundDownloadTask can't use this client certificate configuration: \(reason.description)"
    }
}

// MARK: - Reason.CustomStringConvertible

extension BackgroundDownloadUnsupportedConfigurationError.Reason: CustomStringConvertible {

    public var description: String {
        switch self {
        case .incompleteClientIdentity:
            return "mTLS needs both a certificateChain and a privateKey configured on SecureConnection; only one was."
        case .nonFileBackedSource:
            return
                """
                certificateChain and privateKey must both come from a file path -- use \
                Certificate(_:format:)/PrivateKey(_:format:) with a path, not in-memory bytes or a \
                pre-built certificate. Only a path is guaranteed to still exist to rebuild the \
                identity from after a relaunch.
                """
        case .passwordProtectedPrivateKey:
            return
                """
                a password-protected private key can't be used here -- rebuilding the identity \
                after a relaunch would need the password again, and neither the decrypted key nor \
                the password itself is persisted. Use an unencrypted private key file instead.
                """
        case .spkiPinningAlgorithmNotSupported:
            return
                """
                SPKIPinning here only supports SHA-256, SHA-384, or SHA-512 -- use \
                SPKIHash(_:)/SPKIHash(_:algorithm:) with one of those instead of a custom \
                Crypto.HashFunction.
                """
        }
    }
}

#endif
