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

            let parsed =
                values
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

            let matching = orderedMatches(for: origin, now: now)

            guard !matching.isEmpty else {
                return nil
            }

            for index in matching {
                cookies[index].lastAccess = now
            }

            return
                matching
                .map { "\(cookies[$0].name)=\(cookies[$0].value)" }
                .joined(separator: "; ")
        }

        package func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            cookies.removeAll()
        }

        /// The stored cookies that have not expired, in the order they were first stored.
        package func snapshot(now: Date = Date()) -> [Cookie] {
            lock.lock()
            defer { lock.unlock() }
            return cookies.filter { !$0.isExpired(at: now) }
        }

        /// The cookies a request to `url` would be sent, in the order they would be sent.
        ///
        /// Does not count as a use: `lastAccess` is not touched, so looking at a jar never changes
        /// which cookie it evicts next.
        package func cookies(for url: URL, now: Date = Date()) -> [Cookie] {
            guard let origin = Self.origin(of: url) else {
                return []
            }

            lock.lock()
            defer { lock.unlock() }

            return orderedMatches(for: origin, now: now).map { cookies[$0] }
        }

        /// Stores a cookie that did not come from a response.
        ///
        /// It is replaced, deleted by an expired one, and counted against the limits like a
        /// received cookie, and refused by the rules ``Internals/Cookie/rejection(of:publicSuffixList:)``
        /// states. What it leaves out is what needs an origin: that the `Domain` covers the host
        /// that sent it, that `Secure` came over TLS, that plaintext cannot shadow a `Secure`
        /// cookie, and the per-response limit.
        package func insert(_ cookie: Cookie, now: Date = Date()) throws(Cookie.Rejection) {
            var cookie = cookie
            cookie.domain = Cookie.normalizedDomain(cookie.domain)

            if let rejection = Cookie.rejection(of: cookie, publicSuffixList: publicSuffixList) {
                throw rejection
            }

            // The caller has just used it, whatever `creation` they gave.
            cookie.lastAccess = now

            lock.lock()
            defer { lock.unlock() }

            insert(cookie, from: nil, now: now)
        }

        /// Adds the cookies of a persisted snapshot, and returns how many it did not.
        ///
        /// Each goes through ``Internals/Cookie/rejection(of:publicSuffixList:)`` against this
        /// storage's list, and one that fails is skipped. Unlike `insert`, it never deletes (an
        /// expired cookie is skipped, not taken for a deletion), and never replaces: a cookie the
        /// storage holds is newer than a persisted one. Only the first
        /// ``maximumCookies`` are considered, so that a snapshot cannot cost more than a jar holds.
        @discardableResult
        package func restore(_ restored: [Cookie], now: Date = Date()) -> Int {
            var added = 0

            lock.lock()
            defer { lock.unlock() }

            for var cookie in restored.prefix(Self.maximumCookies) {
                cookie.domain = Cookie.normalizedDomain(cookie.domain)
                cookie.lastAccess = cookie.creation

                guard
                    !cookie.isExpired(at: now),
                    Cookie.rejection(of: cookie, publicSuffixList: publicSuffixList) == nil,
                    !cookies.contains(where: { $0.hasSameIdentity(as: cookie) })
                else {
                    continue
                }

                cookies.append(cookie)
                added += 1
                enforceLimits(domain: cookie.domain, now: now)
            }

            return restored.count - added
        }

        /// Removes the cookies with this name, domain and path, host-only or not.
        @discardableResult
        package func remove(name: String, domain: String, path: String) -> Bool {
            let domain = Cookie.normalizedDomain(domain)

            lock.lock()
            defer { lock.unlock() }

            return removeMatching { $0.name == name && $0.domain == domain && $0.path == path } > 0
        }

        /// Removes the cookie that `cookie` would replace.
        @discardableResult
        package func remove(_ cookie: Cookie) -> Bool {
            var cookie = cookie
            cookie.domain = Cookie.normalizedDomain(cookie.domain)

            lock.lock()
            defer { lock.unlock() }

            return removeMatching { $0.hasSameIdentity(as: cookie) } > 0
        }

        /// Removes the cookies a request to `host` would match by domain, whatever their path or
        /// `Secure`, and with `includingSubdomains` the ones of the hosts below it too.
        package func removeAll(forHost host: String, includingSubdomains: Bool) {
            let host = Cookie.normalizedDomain(host)

            guard !host.isEmpty else {
                return
            }

            // An address has no hosts below it: `5.127.0.0.1` is not under `127.0.0.1`.
            let includingSubdomains = includingSubdomains && !Cookie.isIPAddress(host)

            lock.lock()
            defer { lock.unlock() }

            removeMatching { cookie in
                let matches =
                    cookie.hostOnly
                    ? cookie.domain == host
                    : Cookie.domainMatches(host: host, domain: cookie.domain)

                return matches || (includingSubdomains && Cookie.domainMatches(host: cookie.domain, domain: host))
            }
        }

        // MARK: - Private methods

        /// RFC 6265 section 5.3, steps 11 and 12. Expects the lock to be held.
        private func insert(_ cookie: Cookie, from origin: Cookie.Origin?, now: Date) {
            let existing = cookies.firstIndex { $0.hasSameIdentity(as: cookie) }

            // A response over an insecure connection cannot replace, delete or shadow a Secure cookie
            // (RFC 6265bis section 5.7, step 16): not only the one it would replace, but any that
            // has the name, whose domain it may be a parent or a child of, and whose path it
            // reaches. Otherwise `sid=evil; Domain=example.com; Path=/app` from plaintext would sit
            // beside a Secure `sid` and be sent first.
            if let origin, !origin.isSecure, cookies.contains(where: { isSecureCookie($0, shadowedBy: cookie) }) {
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

        /// The indices of the unexpired cookies that belong on a request from `origin`, in the order
        /// they are sent: longer paths first, then the ones created earlier (RFC 6265 5.4). Expects
        /// the lock to be held.
        private func orderedMatches(for origin: Cookie.Origin, now: Date) -> [Int] {
            var matching: [Int] = []

            for (index, cookie) in cookies.enumerated()
            where !cookie.isExpired(at: now)
                && cookie.matches(host: origin.host, path: origin.path, isSecure: origin.isSecure)
            {
                matching.append(index)
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

            return matching
        }

        /// Expects the lock to be held.
        @discardableResult
        private func removeMatching(_ predicate: (Cookie) -> Bool) -> Int {
            let before = cookies.count
            cookies.removeAll(where: predicate)
            return before - cookies.count
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
                evictLeastRecentlyUsed(
                    while: { $0.filter(sameDomain).count > Self.maximumCookiesPerDomain },
                    where: sameDomain
                )
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
                guard
                    let oldest = cookies.indices
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
