//
// See LICENSE for this package's licensing information.
//

import Foundation

extension Internals {

    /// The cookies of one `CookieJar`: stores what the responses' `Set-Cookie` headers say, and
    /// answers with the `Cookie` header a request is owed.
    ///
    /// A synchronous, lock-protected reference type rather than an actor: a response head must be
    /// stored before the redirect that follows it computes its own `Cookie` header, and before the
    /// caller sees the response, on a SwiftNIO event loop that cannot suspend.
    ///
    /// It belongs to whoever created it and is attached to a request through its session, not
    /// keyed by anything the client pool knows: it never fragments the pool and cannot outlive, or
    /// be dropped before, the caller that owns it.
    package final class CookieStorage: @unchecked Sendable {

        // MARK: - Internal static properties

        /// RFC 6265bis section 5.4's per-domain limit.
        package static let maximumCookiesPerDomain = 50

        /// RFC 6265bis section 5.4's total limit.
        package static let maximumCookies = 3_000

        /// The most cookies one response may set. One response from a host with many labels can
        /// otherwise set the per-domain limit's worth for every parent domain it may name, and
        /// evict the cookies of every other site to make room.
        package static let maximumCookiesPerResponse = 50

        // MARK: - Private properties

        private let lock = NSLock()
        private let publicSuffixList: PublicSuffixList?
        private var cookies: [Cookie] = []

        // MARK: - Inits

        package init(publicSuffixList: PublicSuffixList? = nil) {
            self.publicSuffixList = publicSuffixList
        }

        // MARK: - Internal methods

        /// Stores the cookies of the `Set-Cookie` values of the response to a request to `url`.
        ///
        /// - Parameter areFolded: Whether a transport joined repeated `Set-Cookie` headers into one
        ///   value, as `HTTPURLResponse.allHeaderFields` does, so each of `setCookieValues` may be
        ///   several cookies. `false` for a transport that keeps them apart: a comma in one of
        ///   those is part of the cookie.
        package func store(
            setCookieValues: [String],
            for url: URL,
            areFolded: Bool = false,
            now: Date = Date()
        ) {
            guard let origin = Self.origin(of: url) else {
                return
            }

            let values = areFolded ? setCookieValues.flatMap(SetCookieSplitter.split) : setCookieValues

            let parsed = values
                .prefix(Self.maximumCookiesPerResponse)
                .compactMap { Cookie.parse($0, from: origin, now: now, publicSuffixList: publicSuffixList) }

            guard !parsed.isEmpty else {
                return
            }

            lock.lock()
            defer { lock.unlock() }

            for cookie in parsed {
                insert(cookie, from: origin, now: now)
            }
        }

        /// The value of the `Cookie` header for a request to `url`, or `nil` when no cookie
        /// applies.
        ///
        /// Cookies with longer paths come first, then the ones created earlier (RFC 6265 5.4).
        package func cookieHeader(for url: URL, now: Date = Date()) -> String? {
            guard let origin = Self.origin(of: url) else {
                return nil
            }

            lock.lock()
            defer { lock.unlock() }

            cookies.removeAll { $0.isExpired(at: now) }

            var matching: [Int] = []

            for (index, cookie) in cookies.enumerated()
            where cookie.matches(host: origin.host, path: origin.path, isSecure: origin.isSecure) {
                matching.append(index)
            }

            guard !matching.isEmpty else {
                return nil
            }

            // Cookies set by one response share a creation time, and `sort` is not stable: the
            // position in the store, which is the order they were stored in, breaks the tie.
            matching.sort {
                let (lhs, rhs) = (cookies[$0], cookies[$1])

                if lhs.path.count != rhs.path.count {
                    return lhs.path.count > rhs.path.count
                }

                return lhs.creation != rhs.creation ? lhs.creation < rhs.creation : $0 < $1
            }

            for index in matching {
                cookies[index].lastAccess = now
            }

            return matching
                .map { "\(cookies[$0].name)=\(cookies[$0].value)" }
                .joined(separator: "; ")
        }

        package func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            cookies.removeAll()
        }

        /// The stored cookies that have not expired, for tests and diagnostics.
        package func snapshot(now: Date = Date()) -> [Cookie] {
            lock.lock()
            defer { lock.unlock() }
            return cookies.filter { !$0.isExpired(at: now) }
        }

        // MARK: - Private methods

        /// RFC 6265 section 5.3, steps 11 and 12. Expects the lock to be held.
        private func insert(_ cookie: Cookie, from origin: Cookie.Origin, now: Date) {
            let existing = cookies.firstIndex {
                $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
                    && $0.hostOnly == cookie.hostOnly
            }

            // A response over an insecure connection cannot replace, delete or shadow a Secure cookie
            // (RFC 6265bis section 5.7, step 16): not only the one it would replace, but any that
            // has the name, whose domain it may be a parent or a child of, and whose path it
            // reaches. Otherwise `sid=evil; Domain=example.com; Path=/app` from plaintext would sit
            // beside a Secure `sid` and be sent first.
            if !origin.isSecure, cookies.contains(where: { isSecureCookie($0, shadowedBy: cookie) }) {
                return
            }

            // An already-expired cookie is a deletion: it evicts its match and is not kept.
            if cookie.isExpired(at: now) {
                if let existing {
                    cookies.remove(at: existing)
                }

                return
            }

            var cookie = cookie

            if let existing {
                cookie.creation = cookies[existing].creation
                cookies[existing] = cookie
            } else {
                cookies.append(cookie)
            }

            enforceLimits(domain: cookie.domain, now: now)
        }

        private func isSecureCookie(_ existing: Cookie, shadowedBy new: Cookie) -> Bool {
            existing.secure
                && existing.name == new.name
                && (Cookie.domainMatches(host: existing.domain, domain: new.domain)
                    || Cookie.domainMatches(host: new.domain, domain: existing.domain))
                && Cookie.pathMatches(requestPath: new.path, cookiePath: existing.path)
        }

        /// Drops expired cookies, then the least recently used, until the limits hold.
        private func enforceLimits(domain: String, now: Date) {
            let sameDomain = { (cookie: Cookie) in cookie.domain == domain }

            if cookies.filter(sameDomain).count > Self.maximumCookiesPerDomain {
                cookies.removeAll { sameDomain($0) && $0.isExpired(at: now) }
                evictLeastRecentlyUsed(while: { $0.filter(sameDomain).count > Self.maximumCookiesPerDomain }, where: sameDomain)
            }

            if cookies.count > Self.maximumCookies {
                cookies.removeAll { $0.isExpired(at: now) }
                evictLeastRecentlyUsed(while: { $0.count > Self.maximumCookies }, where: { _ in true })
            }
        }

        private func evictLeastRecentlyUsed(
            while exceeds: ([Cookie]) -> Bool,
            where isCandidate: (Cookie) -> Bool
        ) {
            while exceeds(cookies) {
                guard let oldest = cookies.indices
                    .filter({ isCandidate(cookies[$0]) })
                    .min(by: { cookies[$0].lastAccess < cookies[$1].lastAccess })
                else {
                    return
                }

                cookies.remove(at: oldest)
            }
        }

        // MARK: - Private static methods

        private static func origin(of relativeURL: URL) -> Cookie.Origin? {
            // AsyncHTTPClient resolves the `Location` of a redirect against the URL it came from and
            // hands the result over as it is: a URL relative to a base. Read as it is, its path is
            // only the relative part (`next`, or nothing for `?page=2`).
            let url = relativeURL.absoluteURL

            guard var host = url.host.map(HostName.ascii), !host.isEmpty else {
                return nil
            }

            // Some Foundations keep the brackets of an IPv6 literal.
            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }

            let scheme = url.scheme?.lowercased()
            let isSecure = scheme == "https" || scheme == "wss" || Cookie.isLoopback(host)

            // The path as it was written: `URL.path` drops a trailing slash, which makes `/app/` look
            // like `/app`, and decodes escapes.
            let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
            let path = encodedPath.isEmpty ? "/" : encodedPath
            return .init(host: host, path: path, isSecure: isSecure)
        }
    }
}
