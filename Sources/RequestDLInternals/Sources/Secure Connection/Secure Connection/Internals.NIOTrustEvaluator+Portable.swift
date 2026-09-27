//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore) && !canImport(Darwin)

import NIOCore
import NIOSSL
import SwiftASN1
import X509

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A minimal `VerifierPolicy` covering the one category of check `RFC5280Policy` deliberately
/// leaves to its caller: that the leaf is actually meant to serve as a *TLS server* certificate.
///
/// Installing `tlsCustomVerification` replaces BoringSSL's own default verification outright,
/// which does enforce the `ssl_server` purpose -- so without this, a certificate whose
/// `ExtendedKeyUsage` names `clientAuth` only (but chains to a trusted, or even pinned, CA and
/// whose SAN matches the host) would be accepted as a server certificate. This mirrors the
/// Darwin-side fix in `Internals.NIOTrustEvaluator+Darwin.swift`, which builds its `SecTrust`
/// with `SecPolicyCreateSSL(true, nil)` (a real SSL server policy) instead of
/// `SecPolicyCreateBasicX509()` for the same reason -- see
/// `InternalsNIOTrustEvaluatorTests.tlsCustomVerification_whenLeafLacksServerAuthExtendedKeyUsage_rejects`.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, macCatalyst 13, visionOS 1.0, *)
private struct ServerAuthExtendedKeyUsagePolicy: VerifierPolicy {
    var verifyingCriticalExtensions: [ASN1ObjectIdentifier] {
        [.X509ExtensionID.extendedKeyUsage]
    }

    mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        let extendedKeyUsage: ExtendedKeyUsage?
        do {
            extendedKeyUsage = try chain.leaf.extensions.extendedKeyUsage
        } catch {
            // Present but undecodable: fail closed rather than silently letting an
            // unparseable purpose restriction through.
            return .failsToMeetPolicy(
                reason: "leaf certificate's extendedKeyUsage extension could not be parsed: \(error)"
            )
        }

        guard let extendedKeyUsage else {
            // No EKU extension at all leaves the certificate's purpose unrestricted per RFC
            // 5280 §4.2.1.12, matching both `RFC5280Policy` and the Darwin-side
            // `SecPolicyCreateSSL(true, nil)` behavior.
            return .meetsPolicy
        }

        guard extendedKeyUsage.contains(.serverAuth) || extendedKeyUsage.contains(.any) else {
            return .failsToMeetPolicy(
                reason: "leaf certificate's extendedKeyUsage (\(extendedKeyUsage)) does not include serverAuth"
            )
        }

        return .meetsPolicy
    }
}

extension Internals.NIOTrustEvaluator {

    /// Off Darwin there's no `Security.framework` to hand chain-of-trust validation off to, so
    /// this replicates it with `swift-certificates`, using `RFC5280Policy` for the same category
    /// of checks NIOSSL's own BoringSSL-backed default path performs (chain building, signature,
    /// validity period, basic constraints), plus `ServerAuthExtendedKeyUsagePolicy` for the
    /// server-auth purpose check NIOSSL's own default verification would otherwise have
    /// enforced, run *separately* from the SPKI pin check below, so a pin mismatch under
    /// `.audit` can be told apart from an actual broken chain, which must always reject
    /// regardless of policy.
    static func makePortableEvaluator(
        pins: [Internals.SPKIHash],
        isStrict: Bool,
        trustRootCertificates: [NIOSSLCertificate],
        trustRootsAreExclusive: Bool,
        observer: (any TrustDecisionObserver)?
    ) throws -> Internals.NIOTrustEvaluator {
        // A `let`, fully resolved before the closure below captures it. A `var` captured across
        // both this `@Sendable` closure and the `Task` nested inside it doesn't satisfy Swift 6
        // concurrency checking, even though nothing ever mutates it again after this point.
        let rootStore: CertificateStore = {
            var certificates: [Certificate] = []
            for certificate in trustRootCertificates {
                if let x509Certificate = try? Certificate(derEncoded: certificate.toDERBytes()) {
                    certificates.append(x509Certificate)
                }
            }

            // Extend with (or, when nothing else is configured, fall back entirely to) the same
            // distro CA bundle NIOSSL's own `.default` trust roots would have loaded, unless the
            // configured roots are meant to *replace* the system trust store. Mirrors the Darwin
            // evaluator's `trustRootsAreExclusive` handling of `SecTrustSetAnchorCertificatesOnly`,
            // so `additionalTrustRoots` alone stays additive here too instead of silently dropping
            // every publicly-trusted host.
            if !trustRootsAreExclusive {
                certificates += (try? Self.systemDefaultCertificates()) ?? []
            }

            return CertificateStore(certificates)
        }()

        return Internals.NIOTrustEvaluator(
            tlsCustomVerification: { certificates, promise in
                guard let leafCertificate = certificates.first else {
                    promise.succeed(.failed)
                    return
                }

                guard
                    let leafDER = try? leafCertificate.toDERBytes(),
                    let leaf = try? Certificate(derEncoded: leafDER)
                else {
                    promise.succeed(.failed)
                    return
                }

                var intermediateStore = CertificateStore()
                for certificate in certificates.dropFirst() {
                    guard
                        let der = try? certificate.toDERBytes(),
                        let intermediate = try? Certificate(derEncoded: der)
                    else { continue }
                    intermediateStore.append(intermediate)
                }

                Task {
                    var verifier = Verifier(rootCertificates: rootStore) {
                        RFC5280Policy()
                        ServerAuthExtendedKeyUsagePolicy()
                    }

                    switch await verifier.validate(leaf: leaf, intermediates: intermediateStore) {
                    case .validCertificate(let chain):
                        guard Self.leafSatisfiesServerAuthExtendedKeyUsage(leaf) else {
                            // `RFC5280Policy` validates the chain (signatures, validity period,
                            // basic constraints) but, by its own documentation, deliberately
                            // doesn't check `keyUsage`/`extendedKeyUsage`. The Darwin evaluator
                            // enforces the server-auth EKU via `SecPolicyCreateSSL`; mirror that
                            // here so a certificate issued only for another purpose (client auth,
                            // code signing, ...) isn't accepted as a TLS server identity just
                            // because it chains to a trusted root and its SPKI happens to match a
                            // pin. This is a purpose check like chain validity, not a pin-matching
                            // outcome `.audit` is meant to relax, so it always rejects.
                            observer?(TrustDecision(isTrusted: false, pinsMatched: nil))
                            promise.succeed(.failed)
                            return
                        }

                        // `pins.isEmpty` means nothing is configured to pin against, so chain
                        // validity (already established above) is the whole check then, mirroring
                        // the Darwin evaluator's own `guard !pins.isEmpty` short-circuit -- without
                        // it, `matched` is vacuously `false` over an empty pin set and every chain
                        // is rejected under the default `isStrict` policy.
                        guard !pins.isEmpty else {
                            observer?(TrustDecision(isTrusted: true, pinsMatched: nil))
                            promise.succeed(.certificateVerified)
                            return
                        }

                        let matched = chain.contains { certificate in
                            var serializer = DER.Serializer()
                            guard (try? certificate.publicKey.serialize(into: &serializer)) != nil else {
                                return false
                            }
                            let spkiDERBytes = Data(serializer.serializedBytes)
                            return pins.contains { (try? $0.matchesSPKI(spkiDERBytes)) ?? false }
                        }
                        let accepted = matched || !isStrict
                        observer?(TrustDecision(isTrusted: accepted, pinsMatched: matched))
                        promise.succeed(accepted ? .certificateVerified : .failed)

                    case .couldNotValidate:
                        // The chain itself doesn't validate; always rejects, `.audit` only ever
                        // relaxes a pin mismatch, never a broken chain.
                        observer?(TrustDecision(isTrusted: false, pinsMatched: nil))
                        promise.succeed(.failed)
                    }
                }
            }
        )
    }

    /// Whether `leaf` is usable as a TLS server identity per its `ExtendedKeyUsage` extension,
    /// mirroring `SecPolicyCreateSSL(true, nil)`'s enforcement on the Darwin evaluator: a
    /// certificate with no EKU extension at all is unrestricted, but one that declares an EKU
    /// must include `serverAuth` (or the `any` wildcard).
    private static func leafSatisfiesServerAuthExtendedKeyUsage(_ leaf: Certificate) -> Bool {
        let extendedKeyUsage: ExtendedKeyUsage?
        do {
            extendedKeyUsage = try leaf.extensions.extendedKeyUsage
        } catch {
            // Present but undecodable; fail closed rather than treat it as absent.
            return false
        }

        guard let extendedKeyUsage else {
            return true
        }

        return extendedKeyUsage.contains(.serverAuth) || extendedKeyUsage.contains(.any)
    }

    #if os(Android)
    /// Mirrors NIOSSL's own `AndroidCABundle.swift` search heuristic. Android ships its trust
    /// store as a directory of individual PEM certificates, not a single bundle file the way
    /// Linux/FreeBSD do, so `systemDefaultCertificateStore()` below reads every entry in whichever
    /// of these is found instead of parsing one path as a single PEM bundle.
    private static let systemCABundleDirectorySearchPaths = [
        "/apex/com.android.conscrypt/cacerts",  // Android 14+
        "/system/etc/security/cacerts",  // < Android 14
    ]

    private static func systemDefaultCertificates() throws -> [Certificate] {
        // `contentsOfDirectory(atPath:)` itself is the existence/is-a-directory check; it
        // throws for a path that's missing, a plain file, or unreadable, so the first path that
        // doesn't throw is the match, same "first candidate wins" shape as the file-based branch
        // below.
        for directory in systemCABundleDirectorySearchPaths {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }

            var certificates: [Certificate] = []
            for entry in entries {
                guard let pemCertificates = try? NIOSSLCertificate.fromPEMFile(directory + "/" + entry) else {
                    continue
                }
                for certificate in pemCertificates {
                    if let x509Certificate = try? Certificate(derEncoded: certificate.toDERBytes()) {
                        certificates.append(x509Certificate)
                    }
                }
            }
            return certificates
        }

        return []
    }
    #else
    /// A minimal version of NIOSSL's own `LinuxCABundle.swift`/`FreeBSDCABundle.swift` search
    /// heuristics (file-based paths only), kept in sync with NIOSSL's own lists so pinning on
    /// top of the system default trust store resolves the same roots NIOSSL's default path would
    /// have used. Windows and WASI have no entry here because NIOSSL's own
    /// `platformDefaultConfiguration` doesn't load a default trust store on either platform
    /// either, so there's no NIOSSL-native behavior left to mirror.
    private static let systemCABundleFileSearchPaths = [
        "/etc/ssl/certs/ca-certificates.crt",  // Ubuntu, Debian, Arch, Alpine (Linux)
        "/etc/pki/tls/certs/ca-bundle.crt",  // Fedora (Linux)
        "/usr/local/etc/ssl/cert.pem",  // openssl / ca_root_nss (FreeBSD)
        "/etc/ssl/cert.pem",  // base system, FreeBSD 14+
        "/usr/local/share/certs/ca-root-nss.crt",  // ca_root_nss port bundle (FreeBSD)
    ]

    private static func systemDefaultCertificates() throws -> [Certificate] {
        var certificates: [Certificate] = []

        guard
            let path = systemCABundleFileSearchPaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        else {
            return certificates
        }

        for certificate in try NIOSSLCertificate.fromPEMFile(path) {
            if let x509Certificate = try? Certificate(derEncoded: certificate.toDERBytes()) {
                certificates.append(x509Certificate)
            }
        }

        return certificates
    }
    #endif
}

#endif
