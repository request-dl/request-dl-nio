//
// See LICENSE for this package's licensing information.
//

// What a `BackgroundDownloadTask` persists on `URLSessionTask.taskDescription` for a client
// certificate (mTLS) -- deliberately never the private key's own bytes, only the file path it
// lives at. Unlike `Internals.ServerTrustPolicy.Descriptor` (public certificate bytes, fine to
// carry verbatim), embedding key material in a task's plain-text description would be a real
// regression from the Keychain-only handling this package otherwise holds itself to. This is why
// a client identity sourced from `.bytes` (in-memory only, no path to persist) can't be supported
// here at all, and why an identity is rebuilt fresh from disk on every challenge rather than
// cached: the file, not any in-memory state, is the only thing guaranteed to still exist after a
// relaunch.

#if canImport(Darwin)

import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    package struct ClientIdentityDescriptor: Codable, Equatable, Sendable {

        package enum ResolutionError: Swift.Error, CustomStringConvertible, Equatable, Sendable {
            case incompleteClientIdentity
            case nonFileBackedSource
            case passwordProtectedPrivateKey

            package var description: String {
                switch self {
                case .incompleteClientIdentity:
                    return "mTLS needs both a certificateChain and a privateKey; only one was configured."
                case .nonFileBackedSource:
                    return
                        "the certificateChain/privateKey must both come from a file path, not in-memory bytes or pre-built certificates."
                case .passwordProtectedPrivateKey:
                    return "a password-protected private key can't be rebuilt from disk without the password."
                }
            }
        }

        // MARK: - Internal properties

        package let certificateChainFilePath: String
        package let privateKeyFilePath: String
        package let privateKeyFormat: Internals.Certificate.Format

        // MARK: - Inits

        package init(
            certificateChainFilePath: String,
            privateKeyFilePath: String,
            privateKeyFormat: Internals.Certificate.Format
        ) {
            self.certificateChainFilePath = certificateChainFilePath
            self.privateKeyFilePath = privateKeyFilePath
            self.privateKeyFormat = privateKeyFormat
        }

        // MARK: - Internal methods

        /// `nil` when `secureConnection` configures no client identity at all -- the common case,
        /// and not an error.
        package static func resolve(from secureConnection: Internals.SecureConnection) throws -> Self? {
            switch (secureConnection.certificateChain, secureConnection.privateKey) {
            case (nil, nil):
                return nil

            case (.some(let certificateChain), .some(.privateKey(let privateKey))):
                guard case .file(let certificateChainFilePath) = certificateChain else {
                    throw ResolutionError.nonFileBackedSource
                }

                guard case .file(let privateKeyFilePath) = privateKey.source else {
                    throw ResolutionError.nonFileBackedSource
                }

                guard privateKey.password == nil else {
                    throw ResolutionError.passwordProtectedPrivateKey
                }

                return Self(
                    certificateChainFilePath: certificateChainFilePath,
                    privateKeyFilePath: privateKeyFilePath,
                    privateKeyFormat: privateKey.format
                )

            case (.some, nil), (nil, .some):
                throw ResolutionError.incompleteClientIdentity
            }
        }

        /// Rebuilds a `SecIdentity` from disk, via the same Keychain round-trip
        /// `Internals.URLSessionIdentityPolicy` uses -- safe to call repeatedly (the Keychain
        /// label is content-derived, so re-adding the same identity is a no-op success, not a
        /// duplicate), and expected to be: this runs fresh on every client-certificate challenge,
        /// live or after a relaunch alike, with the caller removing the handle again once it's
        /// done answering.
        package func makeIdentity() throws -> (
            handle: Internals.RawBytesIdentityBuilder.Handle, intermediates: [SecCertificate]
        ) {
            let derCertificates = try Internals.CertificateChain.file(certificateChainFilePath).build().map {
                source -> Data in
                guard case .certificate(let certificate) = source else {
                    preconditionFailure(
                        "Internals.CertificateChain.build() unexpectedly produced a non-certificate source"
                    )
                }
                return Data(try certificate.toDERBytes())
            }

            guard let leaf = derCertificates.first else {
                throw ResolutionError.incompleteClientIdentity
            }

            let rawKeyBytes: Data
            do {
                rawKeyBytes = try Data(contentsOf: URL(fileURLWithPath: privateKeyFilePath))
            } catch {
                throw SecureFileLoadError(resource: .privateKey, path: privateKeyFilePath, underlying: error)
            }

            let privateKeyDER: Data
            switch privateKeyFormat {
            case .der:
                privateKeyDER = rawKeyBytes
            case .pem:
                privateKeyDER = try Internals.RawBytesIdentityBuilder.privateKeyDER(fromPEM: rawKeyBytes)
            }

            let handle = try Internals.RawBytesIdentityBuilder.makeIdentity(
                certificateDER: leaf,
                privateKeyDER: privateKeyDER
            )
            let intermediates = try derCertificates.dropFirst().map {
                try Internals.RawBytesIdentityBuilder.certificate(fromDER: $0)
            }

            return (handle, intermediates)
        }
    }
}

#endif
