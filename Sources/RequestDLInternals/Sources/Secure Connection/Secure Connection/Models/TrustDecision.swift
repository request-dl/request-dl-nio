//
// See LICENSE for this package's licensing information.
//

/// A snapshot of one TLS trust evaluation's outcome, handed to a configured
/// ``TrustDecisionObserver`` right after a peer certificate chain has been evaluated -- purely
/// informational, produced *after* the accept/reject decision it describes has already been made.
public struct TrustDecision: Sendable, Equatable {

    /// Whether the peer's certificate chain was ultimately trusted -- the same accept/reject
    /// outcome the connection itself acts on.
    public let isTrusted: Bool

    /// Whether SPKI pinning was configured for this connection and, if so, whether the presented
    /// chain matched one of the configured pins. `nil` when no pins were configured at all, in
    /// which case `isTrusted` reflects chain validity alone.
    public let pinsMatched: Bool?

    package init(isTrusted: Bool, pinsMatched: Bool?) {
        self.isTrusted = isTrusted
        self.pinsMatched = pinsMatched
    }
}
