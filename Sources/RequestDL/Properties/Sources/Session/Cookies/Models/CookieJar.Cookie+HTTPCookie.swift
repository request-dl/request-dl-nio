//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(FoundationNetworking) || canImport(Darwin)

#if !canImport(FoundationNetworking)
import Foundation
#endif

extension CookieJar.Cookie {

    /// Creates a cookie from a Foundation `HTTPCookie`, to move cookies from `HTTPCookieStorage` or a
    /// web view's cookie store into a jar.
    ///
    /// `HTTPCookie` has no host-only flag: a domain that starts with a dot is the one of a cookie
    /// that applies to subdomains, and one that does not is host-only. What it does not carry is
    /// lost: ``creation`` is now, and a cookie with no expiry is a session cookie.
    ///
    /// Building a cookie is not a way around the checks: ``CookieJar/insert(_:)`` still applies them.
    public init(_ cookie: HTTPCookie) {
        let isDomainCookie = cookie.domain.hasPrefix(".")

        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: isDomainCookie ? String(cookie.domain.dropFirst()) : cookie.domain,
            hostOnly: !isDomainCookie,
            path: cookie.path,
            secure: cookie.isSecure,
            httpOnly: cookie.isHTTPOnly,
            expires: cookie.isSessionOnly ? nil : cookie.expiresDate
        )
    }

    /// The cookie as a Foundation `HTTPCookie`, for a web view's cookie store or `HTTPCookieStorage`,
    /// or `nil` when Foundation refuses it.
    ///
    /// ``creation`` is not carried: `HTTPCookie` has no place for it.
    public var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: hostOnly ? domain : "." + domain,
            .path: path,
        ]

        if secure {
            properties[.secure] = "TRUE"
        }

        if httpOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }

        if let expires {
            properties[.expires] = expires
        } else {
            properties[.discard] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }
}

#endif
