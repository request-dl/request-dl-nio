//
// See LICENSE for this package's licensing information.
//

/// A pluggable strategy for deciding whether -- and how -- to follow HTTP redirects, used via
/// ``Session/redirectStrategy(_:)``.
///
/// Unlike ``Session/disableRedirect()``/``Session/enableRedirectFollow(max:allowCycles:)``, a
/// strategy gets a chance to inspect every redirect-eligible response before it's followed:
/// adjust the outgoing request, refuse the redirect outright, or fail the whole request with a
/// custom error.
///
/// ```swift
/// struct SameHostRedirects: RedirectStrategy {
///
///     func redirectDecision(for context: RedirectContext) throws -> RedirectDecision {
///         guard context.redirectCount < 5 else {
///             return .doNotFollow
///         }
///
///         return .follow(context.redirectRequest)
///     }
/// }
/// ```
///
/// - Important: A single strategy instance is shared across every request made under it,
/// including concurrently -- if it holds mutable state (e.g. an audit log, a shared allow-list),
/// synchronize it yourself (an `actor`, or a class using a lock). Per-request state doesn't need
/// that: ``RedirectContext/history`` already carries everything tracked so far for the *current*
/// logical request, so most policies (host allow-listing, loop bounds, auditing) can be
/// implemented statelessly by reading it fresh on each call.
///
/// - Note: Configuring a ``RedirectStrategy`` opts a ``Session`` out of connection-pool reuse
/// across requests -- unlike every other ``Session`` property, a strategy has no meaningful
/// notion of equality to compare against a previously pooled client, so each resolution of a
/// ``Property`` tree that configures one gets a fresh client.
public protocol RedirectStrategy: Sendable {

    ///
    /// Decide whether -- and how -- to follow a redirect.
    ///
    /// - Parameter context: Everything known about the redirect so far. See ``RedirectContext``.
    /// - Returns: Whether -- and with what request -- to follow the redirect.
    /// - Throws: To fail the whole request with a custom error instead of following the redirect
    /// or returning the response that triggered it.
    ///
    func redirectDecision(for context: RedirectContext) throws -> RedirectDecision
}
