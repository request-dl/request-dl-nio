//
// See LICENSE for this package's licensing information.
//

/// Adapts a closure to ``RedirectStrategy``, backing ``Session/onRedirect(_:)``.
struct ClosureRedirectStrategy: RedirectStrategy {

    let handler: @Sendable (RedirectContext) throws -> RedirectDecision

    func redirectDecision(for context: RedirectContext) throws -> RedirectDecision {
        try handler(context)
    }
}
