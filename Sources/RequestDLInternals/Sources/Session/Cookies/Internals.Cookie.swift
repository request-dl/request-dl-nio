//
// See LICENSE for this package's licensing information.
//

import Foundation

extension Internals {

    /// A cookie held by an `Internals.CookieStorage`, parsed from a `Set-Cookie` header the way
    /// RFC 6265 section 5 describes.
    ///
    /// This is deliberately not `HTTPClient.Cookie`: that parser lives behind the `NIOTransport`
    /// trait, forgets whether the `Domain` attribute was present (a host-only cookie and a domain
    /// cookie are different things), defaults the path to `/` instead of the RFC's default-path,
    /// strips the quotes of a value (so it would not be sent back verbatim), and stores `Max-Age`
    /// without the instant it was received.
    package struct Cookie: Sendable, Equatable {

        // MARK: - Internal static properties

        /// The largest `name=value` a cookie may have, in bytes. RFC 6265bis section 5.4.
        package static let maximumNameValueLength = 4_096

        /// The largest value an attribute may have, in bytes. RFC 6265bis section 5.4.
        package static let maximumAttributeValueLength = 1_024

        // MARK: - Internal properties

        package var name: String
        package var value: String

        /// Lowercased, without a leading dot.
        package var domain: String

        /// `true` when the server sent no `Domain` attribute: only that exact host gets the cookie.
        package var hostOnly: Bool
        package var path: String
        package var secure: Bool
        package var httpOnly: Bool

        /// `nil` for a session cookie, which this storage keeps until it is cleared.
        package var expires: Date?
        package var creation: Date
        package var lastAccess: Date

        // MARK: - Inits

        package init(
            name: String,
            value: String,
            domain: String,
            hostOnly: Bool,
            path: String,
            secure: Bool = false,
            httpOnly: Bool = false,
            expires: Date? = nil,
            creation: Date,
            lastAccess: Date? = nil
        ) {
            self.name = name
            self.value = value
            self.domain = domain
            self.hostOnly = hostOnly
            self.path = path
            self.secure = secure
            self.httpOnly = httpOnly
            self.expires = expires
            self.creation = creation
            self.lastAccess = lastAccess ?? creation
        }

        // MARK: - Internal methods

        package func isExpired(at now: Date) -> Bool {
            guard let expires else {
                return false
            }

            return expires <= now
        }

        /// Whether this cookie belongs on a request to `host`/`path` over a connection that is, or
        /// is not, `isSecure`. RFC 6265 section 5.4, step 1.
        package func matches(host: String, path requestPath: String, isSecure: Bool) -> Bool {
            if hostOnly {
                guard host == domain else {
                    return false
                }
            } else if !Cookie.domainMatches(host: host, domain: domain) {
                return false
            }

            guard Cookie.pathMatches(requestPath: requestPath, cookiePath: path) else {
                return false
            }

            return !secure || isSecure
        }

        // MARK: - Internal static methods

        /// RFC 6265 section 5.1.3.
        package static func domainMatches(host: String, domain: String) -> Bool {
            if host == domain {
                return true
            }

            guard !isIPAddress(host), host.hasSuffix(domain) else {
                return false
            }

            let boundary = host.index(host.endIndex, offsetBy: -domain.count - 1, limitedBy: host.startIndex)
            return boundary.map { host[$0] == "." } ?? false
        }

        /// RFC 6265 section 5.1.4, `path-match`.
        package static func pathMatches(requestPath: String, cookiePath: String) -> Bool {
            if requestPath == cookiePath {
                return true
            }

            guard requestPath.hasPrefix(cookiePath) else {
                return false
            }

            if cookiePath.hasSuffix("/") {
                return true
            }

            let next = requestPath[requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)]
            return next == "/"
        }

        /// RFC 6265 section 5.1.4, `default-path`.
        package static func defaultPath(of requestPath: String) -> String {
            guard requestPath.hasPrefix("/") else {
                return "/"
            }

            guard let lastSlash = requestPath.lastIndex(of: "/"), lastSlash != requestPath.startIndex else {
                return "/"
            }

            return String(requestPath[..<lastSlash])
        }

        /// Whether `host` is an IPv4 or IPv6 literal, to which a `Domain` attribute never applies.
        package static func isIPAddress(_ host: String) -> Bool {
            if host.contains(":") {
                return true
            }

            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 4 && parts.allSatisfy { part in
                !part.isEmpty && part.count <= 3 && part.allSatisfy { $0.isASCII && $0.isNumber }
            }
        }

        /// Whether a connection to `host` is one a `Secure` cookie may travel on without TLS.
        package static func isLoopback(_ host: String) -> Bool {
            host == "localhost" || host.hasSuffix(".localhost") || host == "::1" || host.hasPrefix("127.")
        }
    }
}
