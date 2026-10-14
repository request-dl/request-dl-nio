//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(NIOCore)
extension Session {

    /// The HTTP versions a session is allowed to negotiate. See ``Session/httpVersion(_:)``.
    public enum HTTPVersion: Sendable, Hashable {

        /// Only HTTP/1.1, even when the server offers HTTP/2.
        ///
        /// `URLSession` has no way to opt out of HTTP/2, so a session pinned to this version
        /// never resolves to ``Session/Executor/urlSession``.
        case http1Only

        /// Negotiates the best version both sides support: HTTP/2 when the server offers it over
        /// ALPN, HTTP/1.1 otherwise. This is what a session does when nothing is configured.
        case automatic

        // MARK: - Internal methods

        func build() -> Internals.HTTPVersion {
            switch self {
            case .http1Only:
                return .http1Only
            case .automatic:
                return .automatic
            }
        }
    }
}
#endif
