//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A snapshot of one TLS trust evaluation's outcome, handed to a configured
/// ``TrustDecisionObserver`` right after a peer certificate chain has been evaluated.
public typealias TrustDecision = RequestDLInternals.TrustDecision
