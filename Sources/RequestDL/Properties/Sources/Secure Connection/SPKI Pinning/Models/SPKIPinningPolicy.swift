//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Failure behavior for ``SPKIPinning`` when a peer's certificate doesn't match any configured pin.
public enum SPKIPinningPolicy: Sendable, Hashable {

    /// Terminate the connection immediately on a pin mismatch. Use in production.
    case strict

    /// Permit the connection on a pin mismatch, for observability only.
    ///
    /// - Warning: Never use in production -- it effectively disables pinning while keeping audit
    /// visibility (e.g. logging) for debugging, testing, or migration windows.
    case audit

    // MARK: - Internal methods

    func build() -> Internals.SPKIPinningPolicy {
        switch self {
        case .strict:
            return .strict
        case .audit:
            return .audit
        }
    }
}
