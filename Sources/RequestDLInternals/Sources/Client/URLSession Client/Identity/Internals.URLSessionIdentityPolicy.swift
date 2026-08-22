//
// See LICENSE for this package's licensing information.
//

// Phase 5e of URLSESSION_TASK.md -- bridges `Internals.SecureConnection` (NIOSSL-shaped) into
// what `URLSession`'s TLS challenge delegate callbacks need (`SecIdentity`/`SecCertificate`/
// `SecTrust`), via `Internals.RawBytesIdentityBuilder`.

#if canImport(Darwin)

import NIOSSL
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    /// The resolved, `URLSession`-ready form of one `Internals.SecureConnection`: a client
    /// identity (if `certificateChain`/`privateKey` were configured) plus the trust roots and
    /// verification mode to apply to the server side of the handshake.
    ///
    /// Built once per `SecureConnection` and held for as long as the owning
    /// `Internals.URLSessionClient` is alive -- mirrors NIOSSL's own per-connection
    /// `TLSConfiguration` caching in `Internals.ClientManager`. The Keychain items backing the
    /// client identity, if any, are removed in `deinit`, not after every request.
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

        private let identityHandle: Internals.RawBytesIdentityBuilder.Handle?
        private let intermediateCertificates: [SecCertificate]
        private let trustedRootCertificates: [SecCertificate]
        private let certificateVerification: NIOSSL.CertificateVerification

        // MARK: - Inits

        package init(_ secureConnection: Internals.SecureConnection) throws {
            switch (secureConnection.certificateChain, secureConnection.privateKey) {
            case (nil, nil):
                identityHandle = nil
                intermediateCertificates = []

            case (.some(let certificateChain), .some(let privateKey)):
                let derCertificates = try Self.derCertificates(from: certificateChain)

                guard let leaf = derCertificates.first else {
                    throw ConfigurationError.emptyCertificateChain
                }

                let privateKeyDER = try Self.rsaPKCS1DER(from: privateKey)

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

            var trustedRootCertificates: [SecCertificate] = []

            if let trustRoots = secureConnection.trustRoots {
                trustedRootCertificates += try Self.certificates(from: trustRoots).map {
                    try RawBytesIdentityBuilder.certificate(fromDER: Data($0.toDERBytes()))
                }
            }

            if let additionalTrustRoots = secureConnection.additionalTrustRoots {
                for additionalTrustRoot in additionalTrustRoots {
                    trustedRootCertificates += try Self.certificates(from: additionalTrustRoot).map {
                        try RawBytesIdentityBuilder.certificate(fromDER: Data($0.toDERBytes()))
                    }
                }
            }

            self.trustedRootCertificates = trustedRootCertificates
            self.certificateVerification = secureConnection.certificateVerification ?? .fullVerification
        }

        deinit {
            if let identityHandle {
                RawBytesIdentityBuilder.remove(identityHandle)
            }
        }

        // MARK: - Internal methods

        /// Answers one TLS challenge (client-certificate or server-trust) for the host this
        /// policy was resolved for. Any other authentication method defers to the system's
        /// default handling.
        package func handle(
            challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            switch challenge.protectionSpace.authenticationMethod {
            case NSURLAuthenticationMethodClientCertificate:
                guard let identityHandle else {
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

            case NSURLAuthenticationMethodServerTrust:
                guard let serverTrust = challenge.protectionSpace.serverTrust else {
                    completionHandler(.performDefaultHandling, nil)
                    return
                }

                if case .none = certificateVerification {
                    // Mirrors NIOSSL's `CertificateVerification.none` (bucket C,
                    // URLSESSION_REPORT.md §4.3) -- deliberately unsafe, opt-in only.
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }

                if certificateVerification == .noHostnameVerification {
                    let policy = SecPolicyCreateSSL(true, nil)
                    _ = SecTrustSetPolicies(serverTrust, policy as CFTypeRef)
                }

                if !trustedRootCertificates.isEmpty {
                    _ = SecTrustSetAnchorCertificates(serverTrust, trustedRootCertificates as CFArray)
                    _ = SecTrustSetAnchorCertificatesOnly(serverTrust, true)
                }

                var evaluationError: CFError?
                let isTrusted = SecTrustEvaluateWithError(serverTrust, &evaluationError)

                if isTrusted {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }

            default:
                completionHandler(.performDefaultHandling, nil)
            }
        }

        // MARK: - Private methods

        /// The leaf certificate (index 0) plus any intermediates, as DER bytes -- reuses NIOSSL's
        /// own PEM/DER + file/bytes parsing (`Internals.CertificateChain.build()`) rather than
        /// re-implementing it, since `CertificateChain.build()` always resolves to
        /// `.certificate(NIOSSLCertificate)` sources regardless of how it was configured.
        private static func derCertificates(from certificateChain: Internals.CertificateChain) throws -> [Data] {
            try certificateChain.build().map { source in
                guard case .certificate(let certificate) = source else {
                    // `Internals.CertificateChain.build()` always resolves to `.certificate`
                    // sources -- every branch loads the certificate(s) up front rather than
                    // deferring to NIOSSL via the (deprecated) `.file` source case.
                    preconditionFailure(
                        "Internals.CertificateChain.build() unexpectedly produced a non-certificate source"
                    )
                }
                return Data(try certificate.toDERBytes())
            }
        }

        private static func certificates(from trustRoots: Internals.TrustRoots) throws -> [NIOSSLCertificate] {
            switch trustRoots {
            case .file(let file):
                return try Internals.Certificate(file, format: .pem).build()
            case .bytes(let bytes):
                return try Internals.Certificate(bytes, format: .pem).build()
            case .certificates(let certificates):
                return try certificates.flatMap { try $0.build() }
            }
        }

        private static func certificates(
            from additionalTrustRoots: Internals.AdditionalTrustRoots
        ) throws -> [NIOSSLCertificate] {
            switch additionalTrustRoots {
            case .file(let file):
                return try Internals.Certificate(file, format: .pem).build()
            case .bytes(let bytes):
                return try Internals.Certificate(bytes, format: .pem).build()
            case .certificates(let certificates):
                return try certificates.flatMap { try $0.build() }
            }
        }

        /// RSA/PKCS#1 only for this first cut (`Internals.RawBytesIdentityBuilder`'s own scope) --
        /// a `.der`-formatted key is assumed to already be raw PKCS#1 DER (SecKeyCreateWithData
        /// fails loudly if it isn't); a password-protected key is rejected outright, since there
        /// is no public API to export a decrypted key back out to DER once NIOSSL has parsed it.
        private static func rsaPKCS1DER(from privateKeySource: Internals.PrivateKeySource) throws -> Data {
            switch privateKeySource {
            case .privateKey(let privateKey):
                guard privateKey.password == nil else {
                    throw RawBytesIdentityBuilder.Error.unsupportedKeyFormat("password-protected key")
                }

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

                switch privateKey.format {
                case .der:
                    return rawBytes
                case .pem:
                    return try RawBytesIdentityBuilder.rsaPKCS1DER(fromPEM: rawBytes)
                }
            }
        }
    }
}

#endif
