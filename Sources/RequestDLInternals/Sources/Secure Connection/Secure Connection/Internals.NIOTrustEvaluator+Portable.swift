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
    /// this replicates it with `swift-certificates` -- `RFC5280Policy` for the same category of
    /// checks NIOSSL's own BoringSSL-backed default path performs (chain building, signature,
    /// validity period, basic constraints), run *separately* from the SPKI pin check below, so a
    /// pin mismatch under `.audit` can be told apart from an actual broken chain, which must
    /// always reject regardless of policy.
    static func makePortableEvaluator(
        pins: [Internals.SPKIHash],
        isStrict: Bool,
        trustRootCertificates: [NIOSSLCertificate]
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
                        promise.succeed((matched || !isStrict) ? .certificateVerified : .failed)

                    case .couldNotValidate:
                        // The chain itself doesn't validate -- always rejects, `.audit` only ever
                        // relaxes a pin mismatch, never a broken chain.
                        promise.succeed(.failed)
                    }
                }
            }
        )
    }

    /// A minimal version of NIOSSL's own `LinuxCABundle.swift` search heuristic (file-based paths
    /// only -- covers Ubuntu/Debian/Arch/Alpine and Fedora) -- kept in sync with NIOSSL's own list
    /// so pinning on top of the system default trust store resolves the same roots NIOSSL's
    /// default path would have used.
    private static let systemCABundleFileSearchPaths = [
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/pki/tls/certs/ca-bundle.crt",
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
}

#endif
