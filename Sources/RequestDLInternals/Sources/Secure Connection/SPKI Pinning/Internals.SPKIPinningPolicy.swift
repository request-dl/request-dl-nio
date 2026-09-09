//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Failure behavior for an SPKI pin mismatch -- `RequestDL`'s own definition, since
    /// AsyncHTTPClient no longer bundles a pinning policy for this package to borrow. Trust
    /// evaluation, including SPKI pinning, is `RequestDL`'s own responsibility, resolved through
    /// `Internals.ServerTrustPolicy`/`Internals.NIOTrustEvaluator`.
    package enum SPKIPinningPolicy: String, Sendable, Hashable {
        /// Terminate the connection immediately on a pin mismatch.
        case strict

        /// Permit the connection on a pin mismatch, for observability only.
        case audit
    }
}
