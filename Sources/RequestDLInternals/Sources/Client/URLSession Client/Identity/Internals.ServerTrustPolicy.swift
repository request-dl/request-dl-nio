//
// See LICENSE for this package's licensing information.
//

// The server-trust half of `Internals.URLSessionIdentityPolicy`, pulled out on its own: unlike
// the client-identity half, it needs no Keychain round-trip, so it can be rebuilt from nothing
// but raw certificate bytes -- which is exactly what a `BackgroundDownloadTask` needs to do after
// a relaunch, with no `Internals.SecureConnection` left in memory to resolve from.

#if canImport(Darwin)

import AsyncHTTPClient
import Crypto
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
            package let spkiPinning: SPKIPinning?

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

            /// SPKI pinning, captured as raw digests rather than `Internals.SPKIHash` -- the
            /// latter type-erases its hash algorithm into a closure that can't survive `Codable`
            /// encoding. `algorithm` is restricted to the three named ones
            /// (`Internals.SPKIHash.KnownAlgorithm`) precisely so a `Descriptor` can recompute the
            /// matching digest of a peer's SPKI bytes after a relaunch with no
            /// `Internals.SecureConnection` in hand -- see ``ServerTrustPolicy/resolve(from:)``,
            /// which throws rather than silently dropping a pin it can't capture this way.
            package struct SPKIPinning: Codable, Equatable, Sendable {
                package let pins: [Pin]
                package let policy: Policy

                package struct Pin: Codable, Equatable, Sendable {
                    package let algorithm: Internals.SPKIHash.KnownAlgorithm
                    package let digest: Data

                    package init(algorithm: Internals.SPKIHash.KnownAlgorithm, digest: Data) {
                        self.algorithm = algorithm
                        self.digest = digest
                    }
                }

                package enum Policy: String, Codable, Equatable, Sendable {
                    case strict
                    case audit
                }

                package init(pins: [Pin], policy: Policy) {
                    self.pins = pins
                    self.policy = policy
                }
            }

            package init(
                trustedRootCertificatesDER: [Data],
                verification: Verification,
                spkiPinning: SPKIPinning? = nil
            ) {
                self.trustedRootCertificatesDER = trustedRootCertificatesDER
                self.verification = verification
                self.spkiPinning = spkiPinning
            }
        }

        /// Thrown by ``descriptor`` when a configured SPKI pin can't be captured into a
        /// `Descriptor` -- only ever `.unpersistableAlgorithm`, for a pin built with a
        /// `Crypto.HashFunction` other than SHA-256/384/512
        /// (`Internals.SPKIHash.KnownAlgorithm`'s three cases). Live, in-process pinning still
        /// works fine with any such algorithm; only surviving a `BackgroundDownloadTask` relaunch
        /// needs the algorithm to be nameable in `Codable` form.
        package enum DescriptorError: Swift.Error, CustomStringConvertible, Sendable {
            case unpersistableAlgorithm

            package var description: String {
                switch self {
                case .unpersistableAlgorithm:
                    return
                        "SPKI pinning under BackgroundDownloadTask only supports SHA-256, SHA-384, or SHA-512 -- the configured SPKIHash uses a different Crypto.HashFunction, which can't be captured into a Codable descriptor that survives an app relaunch."
                }
            }
        }

        // MARK: - Private types

        /// One pin, normalized to a same-process matcher regardless of whether it came from a
        /// live `Internals.SPKIHash` (`resolve(from:)`) or a rebuilt `Descriptor.SPKIPinning.Pin`
        /// (`init(descriptor:)`) -- `handle(challenge:)` doesn't need to know which.
        private struct ResolvedSPKIPin: @unchecked Sendable {
            let matches: @Sendable (Data) -> Bool
        }

        // MARK: - Private properties

        private let trustedRootCertificates: [SecCertificate]
        private let certificateVerification: NIOSSL.CertificateVerification
        private let spkiPins: [ResolvedSPKIPin]
        private let spkiPinningIsStrict: Bool
        private let spkiPinningDescriptor: Descriptor.SPKIPinning?

        // MARK: - Inits

        private init(
            trustedRootCertificates: [SecCertificate],
            certificateVerification: NIOSSL.CertificateVerification,
            spkiPins: [ResolvedSPKIPin],
            spkiPinningIsStrict: Bool,
            spkiPinningDescriptor: Descriptor.SPKIPinning?
        ) {
            self.trustedRootCertificates = trustedRootCertificates
            self.certificateVerification = certificateVerification
            self.spkiPins = spkiPins
            self.spkiPinningIsStrict = spkiPinningIsStrict
            self.spkiPinningDescriptor = spkiPinningDescriptor
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
                certificateVerification: descriptor.verification.nioSSLValue,
                spkiPins: (descriptor.spkiPinning?.pins ?? []).map { pin in
                    ResolvedSPKIPin { spkiDERBytes in
                        Self.digest(spkiDERBytes, algorithm: pin.algorithm) == pin.digest
                    }
                },
                spkiPinningIsStrict: descriptor.spkiPinning?.policy == .strict,
                spkiPinningDescriptor: descriptor.spkiPinning
            )
        }

        // MARK: - Internal properties

        /// The `Codable` snapshot of this exact policy -- everything ``init(descriptor:)`` needs
        /// to rebuild an equivalent one later, with no `Internals.SecureConnection` in hand.
        ///
        /// - Throws: ``DescriptorError/unpersistableAlgorithm`` if `resolve(from:)` was given SPKI
        /// pins built with a `Crypto.HashFunction` other than SHA-256/384/512.
        package func descriptor() throws -> Descriptor {
            if spkiPinningDescriptor == nil, !spkiPins.isEmpty {
                // Only reachable via `resolve(from:)`, whose SPKI pins never populated
                // `spkiPinningDescriptor` because at least one used an unnameable algorithm --
                // `init(descriptor:)` always sets `spkiPinningDescriptor` when `spkiPins` is
                // non-empty, so this branch can't fire for an already-rebuilt policy.
                throw DescriptorError.unpersistableAlgorithm
            }

            return Descriptor(
                trustedRootCertificatesDER: trustedRootCertificates.map { SecCertificateCopyData($0) as Data },
                verification: Descriptor.Verification(certificateVerification),
                spkiPinning: spkiPinningDescriptor
            )
        }

        // MARK: - Internal methods

        /// Resolves trust roots and SPKI pinning straight from a `SecureConnection` -- the same
        /// `Internals.TrustRoots`/`Internals.AdditionalTrustRoots` parsing
        /// `Internals.URLSessionIdentityPolicy` uses for its own server-trust half, shared rather
        /// than duplicated between the two. Every pin's digest is resolved eagerly (base64
        /// decoded, length-checked) here rather than lazily on first challenge, so a malformed pin
        /// throws when the session is configured, not silently on every request afterward.
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

            let isStrict = (secureConnection.tlsPinningPolicy ?? .strict) == .strict

            // Each pin's digest is resolved exactly once here (base64 decoded, length-checked) --
            // both `spkiPins` below (the live matcher, re-fetching this same digest per challenge
            // via `matchesSPKI`) and `spkiPinningDescriptor` reuse it, and a malformed pin throws
            // right here rather than lazily on first challenge or first background schedule.
            let resolvedPins: [(pin: Internals.SPKIHash, digest: Data)] = try (secureConnection.tlsPins ?? []).map {
                ($0, try $0.resolvedDigest())
            }

            let spkiPins = resolvedPins.map { resolved in
                ResolvedSPKIPin { spkiDERBytes in
                    (try? resolved.pin.matchesSPKI(spkiDERBytes)) ?? false
                }
            }

            // `nil` whenever there are no pins at all, or whenever any pin's algorithm isn't one
            // of the three `Internals.SPKIHash.KnownAlgorithm` cases -- deliberately *not* thrown
            // here: an unnameable algorithm still pins correctly for live, in-process use
            // (`URLSessionClient`), it just can't be captured for a `BackgroundDownloadTask` to
            // rebuild after a relaunch. `descriptor()` is what throws, and only if it's actually
            // called with pins present but nothing capturable.
            let spkiPinningDescriptor: Descriptor.SPKIPinning? = {
                guard !resolvedPins.isEmpty else { return nil }

                var pins: [Descriptor.SPKIPinning.Pin] = []
                for resolved in resolvedPins {
                    guard let algorithm = resolved.pin.knownAlgorithm else { return nil }
                    pins.append(.init(algorithm: algorithm, digest: resolved.digest))
                }
                return Descriptor.SPKIPinning(pins: pins, policy: isStrict ? .strict : .audit)
            }()

            return ServerTrustPolicy(
                trustedRootCertificates: trustedRootCertificates,
                certificateVerification: secureConnection.certificateVerification ?? .fullVerification,
                spkiPins: spkiPins,
                spkiPinningIsStrict: isStrict,
                spkiPinningDescriptor: spkiPinningDescriptor
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
                // opt-in only. SPKI pins, like every other check below, don't apply here either:
                // `.none` means trust evaluation itself was opted out of.
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

            guard isTrusted else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            guard !spkiPins.isEmpty else {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }

            let pinsMatched =
                Self.leafSPKIDERBytes(of: serverTrust).map { leafSPKIDERBytes in
                    spkiPins.contains { $0.matches(leafSPKIDERBytes) }
                } ?? false

            if pinsMatched || !spkiPinningIsStrict {
                // `.audit` behaves exactly like AsyncHTTPClient's own SPKI pinning policy: a
                // mismatch (or, here, a leaf the SPKI bytes couldn't even be extracted from) is
                // still accepted, on the assumption this is a deliberate debugging/migration
                // window rather than production traffic.
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        // MARK: - Private methods

        /// The leaf certificate's SPKI (SubjectPublicKeyInfo) structure, DER-encoded -- what an
        /// `Internals.SPKIHash` pin's digest is computed over. Reuses NIOSSL's own
        /// `NIOSSLPublicKey.toSPKIBytes()` on the leaf's DER bytes rather than reconstructing the
        /// SPKI ASN.1 wrapper from a bare `SecKey` export by hand, so a pin configured once
        /// produces the identical digest regardless of which executor (`URLSession` here, plain
        /// NIO/NIOTransportServices elsewhere) ends up carrying the connection. `nil` on any
        /// failure along the way (no certificates in the trust, DER that doesn't round-trip
        /// through NIOSSL, a public key NIOSSL can't export) -- treated the same as "pin
        /// mismatch" by the caller, since none of these are expected to happen for a trust that
        /// `SecTrustEvaluateWithError` already accepted moments earlier.
        private static func leafSPKIDERBytes(of trust: SecTrust) -> Data? {
            guard
                let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                let leaf = chain.first
            else {
                return nil
            }

            let derBytes = [UInt8](SecCertificateCopyData(leaf) as Data)

            guard
                let certificate = try? NIOSSLCertificate(bytes: derBytes, format: .der),
                let publicKey = try? certificate.extractPublicKey(),
                let spkiBytes = try? publicKey.toSPKIBytes()
            else {
                return nil
            }

            return Data(spkiBytes)
        }

        private static func digest(_ data: Data, algorithm: Internals.SPKIHash.KnownAlgorithm) -> Data {
            switch algorithm {
            case .sha256: return Data(SHA256.hash(data: data))
            case .sha384: return Data(SHA384.hash(data: data))
            case .sha512: return Data(SHA512.hash(data: data))
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
    }
}

#endif
