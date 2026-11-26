//
// See LICENSE for this package's licensing information.
//

/// Which redirects a header marked with ``Property/hiddenOnRedirect(_:)`` is removed from.
///
/// The first request always carries the header; the scope decides what happens to the requests
/// sent after a redirect.
public enum RedirectHeaderScope: Sendable, Hashable, CaseIterable {

    /// The header is removed from a redirect that goes to another origin (scheme, host, and port),
    /// as `Authorization`, `Cookie`, `Origin` and `Proxy-Authorization` are, and kept on a redirect
    /// that stays on the origin the request was sent to.
    case otherOrigins

    /// The header is removed from every redirect, the ones that stay on the same origin included.
    case anyRedirect
}
