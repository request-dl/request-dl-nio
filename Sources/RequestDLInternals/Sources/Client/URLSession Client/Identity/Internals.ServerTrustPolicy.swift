//
// See LICENSE for this package's licensing information.
//

// The server-trust half of `Internals.URLSessionIdentityPolicy`, pulled out on its own: unlike
// the client-identity half, it needs no Keychain round-trip, so it can be rebuilt from nothing
// but raw certificate bytes -- which is exactly what a `BackgroundDownloadTask` needs to do after
// a relaunch, with no `Internals.SecureConnection` left in memory to resolve from.

#if canImport(Darwin)

import NIOSSL
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    package final class ServerTrustPolicy: @unchecked Sendable {

        /// A `Codable`, `NIOSSL`-free snapshot of one `ServerTrustPolicy` -- what actually
        /// survives a relaunch. Certificates are carried as raw DER bytes rather than file paths,
        /// since the original source (`.bytes` or `.file`) has already been resolved once by the
        /// time this is built, and a persisted path could stop pointing at the same content (or
        /// anything at all) between one launch and the next.
        package struct Descriptor: Codable, Equatable, Sendable {
            package let trustedRootCertificatesDER: [Data]
            package let verification: Verification

            package enum Verification: String, Codable, Equatable, Sendable {
                case none
                case fullVerification
                case noHostnameVerification

                package init(_ verification: NIOSSL.CertificateVerification) {
                    switch verification {
                    case .none:
                        self = .none
                    case .noHostnameVerification:
                        self = .noHostnameVerification
                    case .fullVerification:
                        self = .fullVerification
                    @unknown default:
                        self = .fullVerification
                    }
                }

                package var nioSSLValue: NIOSSL.CertificateVerification {
                    switch self {
                    case .none: return .none
                    case .fullVerification: return .fullVerification
                    case .noHostnameVerification: return .noHostnameVerification
                    }
                }
            }

            package init(trustedRootCertificatesDER: [Data], verification: Verification) {
                self.trustedRootCertificatesDER = trustedRootCertificatesDER
                self.verification = verification
            }
        }

        // MARK: - Private properties

        private let trustedRootCertificates: [SecCertificate]
        private let certificateVerification: NIOSSL.CertificateVerification

        // MARK: - Inits

        package init(
            trustedRootCertificates: [SecCertificate],
            certificateVerification: NIOSSL.CertificateVerification
        ) {
            self.trustedRootCertificates = trustedRootCertificates
            self.certificateVerification = certificateVerification
        }

        /// Rebuilds a policy from a previously captured ``descriptor``. A certificate that fails
        /// to parse back out of its own DER bytes is dropped silently rather than thrown -- it
        /// was already valid DER when captured (`SecCertificateCopyData` never produces anything
        /// else), so this is not expected to happen in practice, and failing the whole challenge
        /// over one bad anchor would be a worse outcome than trusting one fewer root than
        /// intended.
        package convenience init(descriptor: Descriptor) {
            self.init(
                trustedRootCertificates: descriptor.trustedRootCertificatesDER.compactMap {
                    SecCertificateCreateWithData(nil, $0 as CFData)
                },
                certificateVerification: descriptor.verification.nioSSLValue
            )
        }

        // MARK: - Internal properties

        /// The `Codable` snapshot of this exact policy -- everything ``init(descriptor:)`` needs
        /// to rebuild an equivalent one later, with no `Internals.SecureConnection` in hand.
        package var descriptor: Descriptor {
            Descriptor(
                trustedRootCertificatesDER: trustedRootCertificates.map { SecCertificateCopyData($0) as Data },
                verification: Descriptor.Verification(certificateVerification)
            )
        }

        // MARK: - Internal methods

        /// Resolves trust roots straight from a `SecureConnection` -- the same
        /// `Internals.TrustRoots`/`Internals.AdditionalTrustRoots` parsing
        /// `Internals.URLSessionIdentityPolicy` uses for its own server-trust half, shared rather
        /// than duplicated between the two.
        package static func resolve(from secureConnection: Internals.SecureConnection) throws -> ServerTrustPolicy {
            var trustedRootCertificates: [SecCertificate] = []

            if let trustRoots = secureConnection.trustRoots {
                trustedRootCertificates += try certificates(from: trustRoots).map {
                    try RawBytesIdentityBuilder.certificate(fromDER: Data($0.toDERBytes()))
                }
            }

            if let additionalTrustRoots = secureConnection.additionalTrustRoots {
                for additionalTrustRoot in additionalTrustRoots {
                    trustedRootCertificates += try certificates(from: additionalTrustRoot).map {
                        try RawBytesIdentityBuilder.certificate(fromDER: Data($0.toDERBytes()))
                    }
                }
            }

            return ServerTrustPolicy(
                trustedRootCertificates: trustedRootCertificates,
                certificateVerification: secureConnection.certificateVerification ?? .fullVerification
            )
        }

        /// Answers a server-trust challenge. Anything else (client-certificate, or any other
        /// authentication method) defers to the system's default handling -- this type only ever
        /// speaks to the server side of a handshake.
        package func handle(
            challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard
                challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                let serverTrust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            if case .none = certificateVerification {
                // Mirrors NIOSSL's `CertificateVerification.none` -- deliberately unsafe,
                // opt-in only.
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
        }

        // MARK: - Private methods

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
    }
}

#endif
