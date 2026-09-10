//
// See LICENSE for this package's licensing information.
//

/// Observes each TLS trust-evaluation decision a secure connection makes, for observability or
/// security-audit logging. Purely informational: a ``TrustDecision`` has already been decided by
/// the time this is called, and nothing it does can change the outcome.
///
/// - Important: Only fires when a trust decision is actually evaluated through RequestDL's own
/// logic rather than the TLS backend's native path. Under `.urlSession`, that's every
/// server-trust challenge; under `.nio`/`.nioTransportServices`, only when something else already
/// requires it (SPKI pinning, `verification(_:)` set to skip hostname verification,
/// `revocationPolicy(_:)` on Apple platforms, additional trust roots, ...). A plain connection
/// with none of those configured resolves through NIOSSL's own native trust-root handling, which
/// this observer never sees.
public protocol TrustDecisionObserver: Sendable, AnyObject {

    ///
    /// Called once per evaluated peer certificate chain, right after its accept/reject decision
    /// has been made.
    ///
    /// - Parameter decision: The trust decision that was just made.
    ///
    func callAsFunction(_ decision: TrustDecision)
}
