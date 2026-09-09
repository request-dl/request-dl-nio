//
// See LICENSE for this package's licensing information.
//

// The shared core `Internals.ServerTrustPolicy` (`.urlSession`) and `Internals.NIOTrustEvaluator`
// (`.nio`/`.nioTransportServices`) both need, extracted after the two independently reimplemented
// the same `SecTrust`-based accept/reject decision for a while -- and had already drifted once:
// `ServerTrustPolicy` handled `.noHostnameVerification` correctly from its very first version,
// while `NIOTrustEvaluator` needed a dedicated fix later to catch up. Neither of the two consumers
// hands off *how* to call `SecTrustEvaluate(WithError|AsyncWithError)` here -- `.urlSession`'s own
// delegate queue makes the synchronous call safe, while `.nio`'s NIO event loop can't block on it
// -- so this only owns what's identical either way: anchoring the trust, swapping in a
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

    /// One SPKI pin, normalized to a same-process matcher regardless of where it came from --
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
    /// `passes(chain:)` is the accept/reject decision once that call already reported the chain
    /// itself as trusted.
    package struct DarwinTrustEvaluation: Sendable {

        // MARK: - Internal properties

        package let trustRootCertificates: [SecCertificate]
        package let pins: [ResolvedSPKIPin]
        package let isStrict: Bool

        // MARK: - Inits

        package init(trustRootCertificates: [SecCertificate], pins: [ResolvedSPKIPin], isStrict: Bool) {
            self.trustRootCertificates = trustRootCertificates
            self.pins = pins
            self.isStrict = isStrict
        }

        // MARK: - Internal methods

        /// Anchors `trust` on `trustRootCertificates` (when any are configured), and -- only when
        /// `skipsHostnameVerification` -- replaces `trust`'s policy with `SecPolicyCreateSSL(true,
        /// nil)`: a real SSL server policy (still checks the server-auth `extendedKeyUsage` and
        /// everything else a certificate presented for TLS server auth normally must satisfy), just
        /// without the hostname match. Deliberately *not* `SecPolicyCreateBasicX509()` -- that's a
        /// bare X.509 chain-of-trust policy with no purpose/EKU checks at all, which is what
        /// `NIOTrustEvaluator`'s Network.framework closure used before this type existed: a wider
        /// relaxation than `.noHostnameVerification` ever asked for. `ServerTrustPolicy` already
        /// used the correct, narrower policy for `.urlSession`; unifying on it here is a real (if
        /// small) tightening for `.nioTransportServices`, not just a refactor.
        package func prepare(_ trust: SecTrust, skipsHostnameVerification: Bool) {
            if skipsHostnameVerification {
                SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil))
            }

            if !trustRootCertificates.isEmpty {
                SecTrustSetAnchorCertificates(trust, trustRootCertificates as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            }
        }

        /// `pins.isEmpty` means nothing is configured to pin against -- chain validity by itself
        /// (already confirmed by the caller's own `SecTrustEvaluate...` call before this runs) is
        /// the whole check then. Otherwise every certificate in `trust`'s chain is checked, leaf
        /// and intermediates alike -- OWASP's recommended backup-pin practice, pinning an
        /// intermediate CA (which rotates far less often than the leaf) alongside or instead of it
        /// -- and a mismatch only rejects under `isStrict`.
        package func passes(chain trust: SecTrust) -> Bool {
            guard !pins.isEmpty else {
                return true
            }

            let matched = Self.chainSPKIDERBytes(of: trust).contains { spkiDERBytes in
                pins.contains { $0.matches(spkiDERBytes) }
            }

            return matched || !isStrict
        }

        // MARK: - Private methods

        /// Every certificate's SPKI (SubjectPublicKeyInfo) structure in `trust`'s chain,
        /// DER-encoded -- what a pin's digest is computed over. Reuses NIOSSL's own
        /// `NIOSSLPublicKey.toSPKIBytes()` on each certificate's DER bytes rather than
        /// reconstructing the SPKI ASN.1 wrapper from a bare `SecKey` export by hand, so a pin
        /// configured once produces the identical digest regardless of which executor
        /// (`.urlSession`, `.nio`, `.nioTransportServices`) ends up carrying the connection.
        /// Certificates that don't round-trip through NIOSSL are dropped rather than failing the
        /// whole chain -- not expected in practice for a trust `SecTrustEvaluate...` already
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
