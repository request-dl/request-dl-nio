//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Observes each TLS trust-evaluation decision a secure connection makes -- for observability or
/// security-audit logging.
///
/// ``TrustDecisionObserver`` is purely informational: a ``TrustDecision`` has already been
/// decided by the time it's called, and nothing it does can change the outcome.
public typealias TrustDecisionObserver = RequestDLInternals.TrustDecisionObserver
