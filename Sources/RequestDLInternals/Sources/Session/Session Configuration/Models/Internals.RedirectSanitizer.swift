//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

extension Internals {

    /// The cross-origin header rule every redirect goes through, whichever executor follows it
    /// and whoever (the executor itself, or a ``Internals/RedirectStrategy``) picked the
    /// destination.
    ///
    /// A redirect to another origin (scheme, host, and port, per RFC 6454) must not carry what
    /// belongs to the origin it came from: credentials (`Authorization`, `Cookie`,
    /// `Proxy-Authorization`), `Origin`, and an explicit `Host`. `Host` selects the virtual host
    /// *at the origin the request was addressed to*; replayed at another origin it routes the
    /// request to whatever virtual host of that server answers to the name, which, behind a
    /// shared CDN or proxy, can belong to somebody else.
    ///
    /// AsyncHTTPClient's own `transformRequestForRedirect` removes the first four but not `Host`,
    /// and `URLSession` removes none of them but `Authorization`. This is what both executors
    /// apply on top.
    package enum RedirectSanitizer {

        // MARK: - Package static properties

        /// The headers that must not follow a request to another origin.
        package static let crossOriginHeaders = [
            "Origin",
            "Cookie",
            "Authorization",
            "Proxy-Authorization",
            "Host",
        ]

        /// ``crossOriginHeaders`` without `Host`: what AsyncHTTPClient's own redirect handling
        /// removes (and `URLSession` removes `Authorization` of) for a redirect to another origin.
        package static let credentialHeaders = [
            "Origin",
            "Cookie",
            "Authorization",
            "Proxy-Authorization",
        ]

        // MARK: - Package static methods

        /// Whether `lhs` and `rhs` share an origin (scheme, host, and port), per RFC 6454.
        ///
        /// Mirrors `AsyncHTTPClient`'s own (internal, so not reachable from here)
        /// `URL.hasTheSameOrigin(as:)`, which its `transformRequestForRedirect` uses for the same
        /// decision. A URL that doesn't parse has no origin to share, so it is not the same.
        package static func isSameOrigin(_ lhs: String, _ rhs: String) -> Bool {
            guard let lhs = URL(string: lhs), let rhs = URL(string: rhs) else {
                return false
            }

            return lhs.hasTheSameOrigin(as: rhs)
        }

        /// Removes ``crossOriginHeaders`` from `headers` when a request that was sent to
        /// `previousURL` is about to be sent to `newURL` instead and the two don't share an origin.
        package static func sanitize(
            _ headers: inout Internals.HTTPHeaders,
            from previousURL: String,
            to newURL: String
        ) {
            guard !isSameOrigin(previousURL, newURL) else {
                return
            }

            for name in crossOriginHeaders {
                headers.remove(name: name)
            }
        }
    }
}

extension URL {

    /// Whether `self` and `other` share an origin (scheme, host, and port), per RFC 6454.
    func hasTheSameOrigin(as other: URL) -> Bool {
        host == other.host && scheme == other.scheme && port == other.port
    }
}
