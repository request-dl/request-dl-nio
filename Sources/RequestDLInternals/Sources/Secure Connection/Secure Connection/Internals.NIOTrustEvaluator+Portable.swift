//
// See LICENSE for this package's licensing information.
//

#if !canImport(Darwin)

import NIOCore
import NIOSSL
import SwiftASN1
import X509

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.NIOTrustEvaluator {

    /// Off Darwin there's no `Security.framework` to hand chain-of-trust validation off to, so
    /// this replicates it with `swift-certificates`, using `RFC5280Policy` for the same category
    /// of checks NIOSSL's own BoringSSL-backed default path performs (chain building, signature,
    /// validity period, basic constraints), run *separately* from the SPKI pin check below, so a
    /// pin mismatch under `.audit` can be told apart from an actual broken chain, which must
    /// always reject regardless of policy.
    static func makePortableEvaluator(
        pins: [Internals.SPKIHash],
        isStrict: Bool,
        trustRootCertificates: [NIOSSLCertificate],
        observer: (any TrustDecisionObserver)?
    ) throws -> Internals.NIOTrustEvaluator {
        // A `let`, fully resolved before the closure below captures it -- a `var` captured across
        // both this `@Sendable` closure and the `Task` nested inside it doesn't satisfy Swift 6
        // concurrency checking, even though nothing ever mutates it again after this point.
        let rootStore: CertificateStore = {
            var store = CertificateStore()
            for certificate in trustRootCertificates {
                if let x509Certificate = try? Certificate(derEncoded: certificate.toDERBytes()) {
                    store.append(x509Certificate)
                }
            }

            // No explicit trust roots configured -- fall back to the same distro CA bundle
            // NIOSSL's own `.default` trust roots would have loaded, so pinning on top of the
            // system default still validates against the system default, not an empty root set.
            if trustRootCertificates.isEmpty {
                store = (try? Self.systemDefaultCertificateStore()) ?? store
            }

            return store
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
                    }

                    switch await verifier.validate(leaf: leaf, intermediates: intermediateStore) {
                    case .validCertificate(let chain):
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
                        // The chain itself doesn't validate -- always rejects, `.audit` only ever
                        // relaxes a pin mismatch, never a broken chain.
                        observer?(TrustDecision(isTrusted: false, pinsMatched: nil))
                        promise.succeed(.failed)
                    }
                }
            }
        )
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

    private static func systemDefaultCertificateStore() throws -> CertificateStore {
        // `contentsOfDirectory(atPath:)` itself is the existence/is-a-directory check -- it
        // throws for a path that's missing, a plain file, or unreadable, so the first path that
        // doesn't throw is the match, same "first candidate wins" shape as the file-based branch
        // below.
        for directory in systemCABundleDirectorySearchPaths {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }

            var store = CertificateStore()
            for entry in entries {
                guard let certificates = try? NIOSSLCertificate.fromPEMFile(directory + "/" + entry) else {
                    continue
                }
                for certificate in certificates {
                    if let x509Certificate = try? Certificate(derEncoded: certificate.toDERBytes()) {
                        store.append(x509Certificate)
                    }
                }
            }
            return store
        }

        return CertificateStore()
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

    private static func systemDefaultCertificateStore() throws -> CertificateStore {
        var store = CertificateStore()

        guard
            let path = systemCABundleFileSearchPaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        else {
            return store
        }

        for certificate in try NIOSSLCertificate.fromPEMFile(path) {
            if let x509Certificate = try? Certificate(derEncoded: certificate.toDERBytes()) {
                store.append(x509Certificate)
            }
        }

        return store
    }
    #endif
}

#endif
