//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Internals-layer counterpart to `RequestDL.RedirectDecision`.
    package enum RedirectDecision: Sendable {
        case follow(Internals.RedirectRequest)
        case doNotFollow
    }
}
