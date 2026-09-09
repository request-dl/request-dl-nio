//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Dispatch
import NIOCore
import NIOSSL
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.NIOTrustEvaluator {

    /// Same shape of validation as `Internals.ServerTrustPolicy.handle(challenge:)`, minus the
    /// `URLAuthenticationChallenge` wrapping: evaluate against the OS trust store (so Certificate
    /// Transparency, revocation, and the continuously-updated root set all keep applying exactly as
    /// they already do for `.urlSession`), then check every certificate in the chain -- leaf and
    /// intermediates alike -- against the configured pins. A chain-validation failure always
    /// rejects, regardless of policy; a pin mismatch only rejects under `.strict`, matching
    /// `ServerTrustPolicy`'s existing semantics (and AsyncHTTPClient's own former SPKI pinning
    /// policy) exactly.
    static func makeDarwinEvaluator(
        pins: [Internals.SPKIHash],
        isStrict: Bool,
        trustRootCertificates: [NIOSSLCertificate]
    ) throws -> Internals.NIOTrustEvaluator {
        let secTrustRoots: [SecCertificate] = trustRootCertificates.compactMap { certificate in
            (try? certificate.toDERBytes()).flatMap {
                SecCertificateCreateWithData(nil, Data($0) as CFData)
            }
        }

        // `SecTrustEvaluateAsyncWithError` must be called from -- and calls back on -- the same
        // queue. This must not run on the NIO event loop thread that invokes these closures: the
        // evaluation can perform network I/O (OCSP), and blocking the event loop would stall every
        // other connection sharing it.
        let queue = DispatchQueue(label: "RequestDL.NIOTrustEvaluator")

        @Sendable
        func matchesAnyPin(chain: [SecCertificate]) -> Bool {
            let chainSPKIDERBytes: [Data] = chain.compactMap { certificate in
                let derBytes = [UInt8](SecCertificateCopyData(certificate) as Data)
                return (try? NIOSSLCertificate(bytes: derBytes, format: .der))?.spkiDERBytes()
            }
            return chainSPKIDERBytes.contains { spkiDERBytes in
                pins.contains { (try? $0.matchesSPKI(spkiDERBytes)) ?? false }
            }
        }

        @Sendable
        func evaluate(trust: SecTrust, completion: @escaping @Sendable (Bool) -> Void) {
            if !secTrustRoots.isEmpty {
                SecTrustSetAnchorCertificates(trust, secTrustRoots as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            }

            queue.async {
                if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
                    SecTrustEvaluateAsyncWithError(trust, queue) { _, isTrusted, _ in
                        guard isTrusted else {
                            completion(false)
                            return
                        }
                        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
                        completion(matchesAnyPin(chain: chain) || !isStrict)
                    }
                } else {
                    SecTrustEvaluateAsync(trust, queue) { _, result in
                        switch result {
                        case .proceed, .unspecified:
                            let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
                            completion(matchesAnyPin(chain: chain) || !isStrict)
                        default:
                            completion(false)
                        }
                    }
                }
            }
        }

        return Internals.NIOTrustEvaluator(
            tlsCustomVerification: { certificates, promise in
                let secCertificates: [SecCertificate] = certificates.compactMap { certificate in
                    (try? certificate.toDERBytes()).flatMap {
                        SecCertificateCreateWithData(nil, Data($0) as CFData)
                    }
                }

                guard !secCertificates.isEmpty else {
                    promise.succeed(.failed)
                    return
                }

                var trust: SecTrust?
                // A plain X.509 policy, deliberately without a hostname -- hostname/SNI matching
                // stays NIOSSL's own separate gate (tied purely to `certificateVerification`,
                // independent of this callback being installed), so this evaluator only needs to
                // own chain-of-trust validation.
                let status = SecTrustCreateWithCertificates(
                    secCertificates as CFArray,
                    SecPolicyCreateBasicX509(),
                    &trust
                )

                guard status == errSecSuccess, let trust else {
                    promise.succeed(.failed)
                    return
                }

                evaluate(trust: trust) { verified in
                    promise.succeed(verified ? .certificateVerified : .failed)
                }
            },
            tlsCustomVerificationNetworkFramework: { trust, complete in
                // Network.framework already attaches its own SNI-aware policy to this `SecTrust`
                // before handing it here -- left untouched, so hostname validation keeps applying
                // exactly as it would without this callback installed.
                evaluate(trust: trust, completion: complete)
            }
        )
    }
}

#endif
