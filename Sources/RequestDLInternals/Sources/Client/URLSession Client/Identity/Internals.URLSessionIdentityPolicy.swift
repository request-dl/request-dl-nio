//
// See LICENSE for this package's licensing information.
//

// Bridges `Internals.SecureConnection` (NIOSSL-shaped) into what `URLSession`'s TLS challenge
// delegate callbacks need (`SecIdentity`/`SecCertificate`/`SecTrust`), via
// `Internals.RawBytesIdentityBuilder`.

#if canImport(Darwin)

import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    /// The resolved, `URLSession`-ready form of one `Internals.SecureConnection`: a client
    /// identity (if `certificateChain`/`privateKey` were configured), composed with an
    /// `Internals.ServerTrustPolicy` for the trust roots/verification mode/SPKI pinning half, the
    /// one part of this that needs no Keychain round-trip, and so is reusable on its own wherever
    /// only that half is needed.
    ///
    /// Built once per `SecureConnection` and held for as long as the owning
    /// `Internals.URLSessionClient` is alive, mirroring NIOSSL's own per-connection
    /// `TLSConfiguration` caching in `Internals.ClientManager`.
    ///
    /// The Keychain items backing the client identity, if any, are released through
    /// `identityHandle`'s own `deinit`, not after every request, and only actually deleted once
    /// every other live `Internals.IdentityHandle` for that same certificate/key pair (e.g.
    /// another `URLSessionIdentityPolicy` instance configured with the same mTLS identity) has
    /// gone away too. See `Internals.IdentityManager`.
    package final class URLSessionIdentityPolicy: @unchecked Sendable {

        package enum ConfigurationError: Swift.Error, CustomStringConvertible, Sendable {
            case incompleteClientIdentity
            case emptyCertificateChain

            package var description: String {
                switch self {
                case .incompleteClientIdentity:
                    return
                        "mTLS under the URLSession executor needs both a certificateChain and a privateKey; only one was configured."
                case .emptyCertificateChain:
                    return "certificateChain was configured but resolved to zero certificates."
                }
            }
        }

        // MARK: - Private properties

        private let identityHandle: Internals.IdentityHandle?
        private let intermediateCertificates: [SecCertificate]
        private let serverTrustPolicy: Internals.ServerTrustPolicy

        // MARK: - Inits

        package init(_ secureConnection: Internals.SecureConnection) throws {
            switch (secureConnection.certificateChain, secureConnection.privateKey) {
            case (nil, nil):
                identityHandle = nil
                intermediateCertificates = []

            case (.some(let certificateChain), .some(let privateKey)):
                let derCertificates = try RawBytesIdentityBuilder.certificateDERs(from: certificateChain)

                guard let leaf = derCertificates.first else {
                    throw ConfigurationError.emptyCertificateChain
                }

                let privateKeyDER = try RawBytesIdentityBuilder.privateKeyDER(from: privateKey)

                identityHandle = try RawBytesIdentityBuilder.makeIdentity(
                    certificateDER: leaf,
                    privateKeyDER: privateKeyDER
                )
                intermediateCertificates = try derCertificates.dropFirst().map {
                    try RawBytesIdentityBuilder.certificate(fromDER: $0)
                }

            case (.some, nil), (nil, .some):
                throw ConfigurationError.incompleteClientIdentity
            }

            self.serverTrustPolicy = try Internals.ServerTrustPolicy.resolve(from: secureConnection)
        }

        // MARK: - Internal methods

        /// Answers one TLS challenge (client-certificate or server-trust).
        ///
        /// - Parameter isConfiguredHost: Whether the challenge's host matches the host this
        ///   policy was resolved for. Server-trust challenges (pinning, custom trust roots,
        ///   revocation, hostname-verification overrides) are evaluated unconditionally, `false`
        ///   included: this connection can end up talking to a different host mid-redirect, and
        ///   the whole point of pinning/custom trust is to reject a server that doesn't present
        ///   the expected certificate -- skipping that check for a redirect target would let
        ///   whoever controls the redirect defeat pinning just by pointing it at any host with an
        ///   otherwise-valid, publicly-trusted certificate. This matches the `.nio` backend, where
        ///   the equivalent checks are installed once at the `HTTPClient.Configuration` level and
        ///   so already apply to every connection the client opens, redirect targets included.
        ///
        ///   A client-certificate credential, by contrast, is only ever presented when
        ///   `isConfiguredHost` is `true`: it identifies us to the server, so handing it to a
        ///   redirect target this policy was never configured for is its own, separate risk this
        ///   method still guards against.
        package func handle(
            challenge: URLAuthenticationChallenge,
            isConfiguredHost: Bool,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
                serverTrustPolicy.handle(challenge: challenge, completionHandler: completionHandler)
                return
            }

            guard isConfiguredHost, let identityHandle else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            completionHandler(
                .useCredential,
                URLCredential(
                    identity: identityHandle.identity,
                    certificates: intermediateCertificates.isEmpty ? nil : intermediateCertificates,
                    persistence: .forSession
                )
            )
        }

    }
}

#endif
