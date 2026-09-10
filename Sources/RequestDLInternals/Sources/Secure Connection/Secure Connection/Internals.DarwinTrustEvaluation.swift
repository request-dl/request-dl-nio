//
// See LICENSE for this package's licensing information.
//

// The shared core `Internals.ServerTrustPolicy` (`.urlSession`) and `Internals.NIOTrustEvaluator`
// (`.nio`/`.nioTransportServices`) both need, extracted after the two independently reimplemented
// the same `SecTrust`-based accept/reject decision for a while, and had already drifted once:
// `ServerTrustPolicy` handled `.noHostnameVerification` correctly from its very first version,
// while `NIOTrustEvaluator` needed a dedicated fix later to catch up. Neither of the two consumers
// hands off *how* to call `SecTrustEvaluate(WithError|AsyncWithError)` here. `.urlSession`'s own
// delegate queue makes the synchronous call safe, while `.nio`'s NIO event loop can't block on it,
// so this only owns what's identical either way: anchoring the trust, swapping in a
// hostname-less policy when asked, and the strict/audit SPKI pin decision once chain validation
// already succeeded.

#if canImport(Darwin)

import NIOSSL
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    /// One SPKI pin, normalized to a same-process matcher regardless of where it came from.
    /// `Internals.ServerTrustPolicy` also needs a `Descriptor`-capturable digest for
    /// `BackgroundDownloadTask` persistence, `Internals.NIOTrustEvaluator` doesn't; both build one
    /// of these to hand to `DarwinTrustEvaluation`, which only ever needs the matcher itself.
    package struct ResolvedSPKIPin: Sendable {
        package let matches: @Sendable (Data) -> Bool

        package init(matches: @escaping @Sendable (Data) -> Bool) {
            self.matches = matches
        }
    }

    /// Shared, `SecTrust`-based trust-root + SPKI pin logic. `prepare(_:skipsHostnameVerification:)`
    /// must run before the caller's own `SecTrustEvaluate(WithError|AsyncWithError)` call;
    /// `evaluate(chain:chainIsTrusted:)` is the accept/reject decision, folding in that call's own
    /// chain-validity result.
    package struct DarwinTrustEvaluation: Sendable {

        // MARK: - Internal properties

        package let trustRootCertificates: [SecCertificate]
        package let pins: [ResolvedSPKIPin]
        package let isStrict: Bool
        package let revocationPolicy: Internals.RevocationPolicy?
        package let observer: (any TrustDecisionObserver)?

        // MARK: - Inits

        package init(
            trustRootCertificates: [SecCertificate],
            pins: [ResolvedSPKIPin],
            isStrict: Bool,
            revocationPolicy: Internals.RevocationPolicy? = nil,
            observer: (any TrustDecisionObserver)? = nil
        ) {
            self.trustRootCertificates = trustRootCertificates
            self.pins = pins
            self.isStrict = isStrict
            self.revocationPolicy = revocationPolicy
            self.observer = observer
        }

        // MARK: - Internal methods

        /// Anchors `trust` on `trustRootCertificates` (when any are configured); replaces or
        /// augments `trust`'s policy array whenever `skipsHostnameVerification` and/or
        /// `revocationPolicy` ask for it.
        ///
        /// `skipsHostnameVerification` swaps in `SecPolicyCreateSSL(true, nil)`: a real SSL server
        /// policy (still checks the server-auth `extendedKeyUsage` and everything else a
        /// certificate presented for TLS server auth normally must satisfy), just without the
        /// hostname match.
        ///
        /// Deliberately *not* `SecPolicyCreateBasicX509()`, a bare X.509 chain-of-trust policy
        /// with no purpose/EKU checks at all: that would be a wider relaxation than
        /// `.noHostnameVerification` ever asked for, accepting a certificate lacking the
        /// server-auth `extendedKeyUsage` that `SecPolicyCreateSSL(true, nil)` correctly rejects
        /// (see `InternalsDarwinTrustEvaluationTests`'s
        /// `prepare_whenSkipsHostnameVerification_stillEnforcesServerAuthExtendedKeyUsage`).
        ///
        /// `revocationPolicy`, when set, is appended to whichever policy array results from the
        /// above. `SecTrustCopyPolicies` reads `trust`'s current array first (its default SSL/
        /// X.509 policy, when `skipsHostnameVerification` didn't just replace it) rather than
        /// dropping it, since `SecTrustSetPolicies` replaces the whole array rather than appending
        /// to it.
        package func prepare(_ trust: SecTrust, skipsHostnameVerification: Bool) {
            if skipsHostnameVerification || revocationPolicy != nil {
                var policies: [SecPolicy]

                if skipsHostnameVerification {
                    policies = [SecPolicyCreateSSL(true, nil)]
                } else {
                    var currentPolicies: CFArray?
                    policies =
                        SecTrustCopyPolicies(trust, &currentPolicies) == errSecSuccess
                        ? (currentPolicies as? [SecPolicy] ?? [])
                        : []
                }

                if let revocationPolicy {
                    policies.append(revocationPolicy.secPolicy)
                }

                SecTrustSetPolicies(trust, policies as CFArray)
            }

            if !trustRootCertificates.isEmpty {
                SecTrustSetAnchorCertificates(trust, trustRootCertificates as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            }
        }

        /// The accept/reject decision, given `chainIsTrusted`, the caller's own
        /// `SecTrustEvaluate(WithError|AsyncWithError)` result for `trust`. Notifies `observer`,
        /// when configured, with the outcome either way, before returning it.
        ///
        /// `pins.isEmpty` means nothing is configured to pin against, so chain validity by itself
        /// is the whole check then. Otherwise every certificate in `trust`'s chain is checked, leaf
        /// and intermediates alike (OWASP's recommended backup-pin practice, pinning an
        /// intermediate CA, which rotates far less often than the leaf, alongside or instead of
        /// it), and a mismatch only rejects under `isStrict`.
        package func evaluate(chain trust: SecTrust, chainIsTrusted: Bool) -> Bool {
            guard chainIsTrusted else {
                observer?(TrustDecision(isTrusted: false, pinsMatched: nil))
                return false
            }

            guard !pins.isEmpty else {
                observer?(TrustDecision(isTrusted: true, pinsMatched: nil))
                return true
            }

            let matched = Self.chainSPKIDERBytes(of: trust).contains { spkiDERBytes in
                pins.contains { $0.matches(spkiDERBytes) }
            }

            let accepted = matched || !isStrict
            observer?(TrustDecision(isTrusted: accepted, pinsMatched: matched))
            return accepted
        }

        // MARK: - Private methods

        /// Every certificate's SPKI (SubjectPublicKeyInfo) structure in `trust`'s chain,
        /// DER-encoded: what a pin's digest is computed over. Reuses NIOSSL's own
        /// `NIOSSLPublicKey.toSPKIBytes()` on each certificate's DER bytes rather than
        /// reconstructing the SPKI ASN.1 wrapper from a bare `SecKey` export by hand, so a pin
        /// configured once produces the identical digest regardless of which executor
        /// (`.urlSession`, `.nio`, `.nioTransportServices`) ends up carrying the connection.
        ///
        /// Certificates that don't round-trip through NIOSSL are dropped rather than failing the
        /// whole chain; that isn't expected in practice for a trust `SecTrustEvaluate...` already
        /// accepted moments earlier.
        private static func chainSPKIDERBytes(of trust: SecTrust) -> [Data] {
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
                return []
            }

            return chain.compactMap { certificate in
                let derBytes = [UInt8](SecCertificateCopyData(certificate) as Data)
                return (try? NIOSSLCertificate(bytes: derBytes, format: .der))?.spkiDERBytes()
            }
        }
    }
}

#endif
