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
    /// `URLAuthenticationChallenge` wrapping. Both delegate the actual trust-root/SPKI pin
    /// decision to the shared `Internals.DarwinTrustEvaluation`, and only own what genuinely
    /// differs between them.
    ///
    /// This evaluator can't call `SecTrustEvaluate(WithError|AsyncWithError)` synchronously the
    /// way `ServerTrustPolicy` does on `.urlSession`'s own delegate queue, since evaluation can
    /// perform network I/O (OCSP), and blocking the NIO event loop that invokes these closures
    /// would stall every other connection sharing it. So it always dispatches onto its own
    /// dedicated queue first.
    static func makeDarwinEvaluator(
        pins: [Internals.SPKIHash],
        isStrict: Bool,
        trustRootCertificates: [NIOSSLCertificate],
        skipsHostnameVerification: Bool,
        revocationPolicy: Internals.RevocationPolicy?,
        observer: (any TrustDecisionObserver)?
    ) throws -> Internals.NIOTrustEvaluator {
        let secTrustRoots: [SecCertificate] = trustRootCertificates.compactMap { certificate in
            (try? certificate.toDERBytes()).flatMap {
                SecCertificateCreateWithData(nil, Data($0) as CFData)
            }
        }

        let resolvedPins = pins.map { pin in
            Internals.ResolvedSPKIPin { spkiDERBytes in
                (try? pin.matchesSPKI(spkiDERBytes)) ?? false
            }
        }

        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: secTrustRoots,
            pins: resolvedPins,
            isStrict: isStrict,
            revocationPolicy: revocationPolicy,
            observer: observer
        )

        // `SecTrustEvaluateAsyncWithError` must be called from, and calls back on, the same
        // queue.
        let queue = DispatchQueue(label: "RequestDL.NIOTrustEvaluator")

        @Sendable
        func evaluate(
            trust: SecTrust,
            skipsHostnameVerification: Bool,
            completion: @escaping @Sendable (Bool) -> Void
        ) {
            evaluation.prepare(trust, skipsHostnameVerification: skipsHostnameVerification)

            queue.async {
                if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
                    SecTrustEvaluateAsyncWithError(trust, queue) { _, isTrusted, _ in
                        completion(evaluation.evaluate(chain: trust, chainIsTrusted: isTrusted))
                    }
                } else {
                    SecTrustEvaluateAsync(trust, queue) { _, result in
                        switch result {
                        case .proceed, .unspecified:
                            completion(evaluation.evaluate(chain: trust, chainIsTrusted: true))
                        default:
                            completion(evaluation.evaluate(chain: trust, chainIsTrusted: false))
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
                // A plain X.509 policy, deliberately without a hostname. Hostname/SNI matching
                // stays NIOSSL's own separate gate (tied purely to `certificateVerification`,
                // independent of this callback being installed), so this evaluator only needs to
                // own chain-of-trust validation. Never affected by `skipsHostnameVerification`:
                // there's no live hostname context on this from-scratch `SecTrust` for
                // `DarwinTrustEvaluation.prepare(_:skipsHostnameVerification:)`'s policy swap to
                // apply to in the first place.
                let status = SecTrustCreateWithCertificates(
                    secCertificates as CFArray,
                    SecPolicyCreateBasicX509(),
                    &trust
                )

                guard status == errSecSuccess, let trust else {
                    promise.succeed(.failed)
                    return
                }

                evaluate(trust: trust, skipsHostnameVerification: false) { verified in
                    promise.succeed(verified ? .certificateVerified : .failed)
                }
            },
            tlsCustomVerificationNetworkFramework: { trust, complete in
                evaluate(trust: trust, skipsHostnameVerification: skipsHostnameVerification, completion: complete)
            }
        )
    }
}

#endif
