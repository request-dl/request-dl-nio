//
// See LICENSE for this package's licensing information.
//

/// The result of a ``RedirectStrategy`` deciding whether -- and how -- to follow a redirect.
public enum RedirectDecision: Sendable {

    /// Follow the redirect using the given request.
    case follow(RedirectRequest)

    /// Do not follow the redirect; the response that triggered it is returned as-is.
    case doNotFollow
}
