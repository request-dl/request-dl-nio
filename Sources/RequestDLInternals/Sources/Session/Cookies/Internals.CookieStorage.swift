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
        /// Every element may itself be several cookies folded together by the transport.
        package func store(
            setCookieValues: [String],
            for url: URL,
            now: Date = Date()
        ) {
            guard let origin = Self.origin(of: url) else {
                return
            }

            let parsed = setCookieValues
                .flatMap(SetCookieSplitter.split)
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

            matching.sort {
                let (lhs, rhs) = (cookies[$0], cookies[$1])
                return lhs.path.count != rhs.path.count
                    ? lhs.path.count > rhs.path.count
                    : lhs.creation < rhs.creation
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

            // A response over an insecure connection cannot replace, or delete, a Secure cookie.
            if let existing, cookies[existing].secure, !origin.isSecure {
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

        private static func origin(of url: URL) -> Cookie.Origin? {
            guard var host = url.host?.lowercased(), !host.isEmpty else {
                return nil
            }

            // Some Foundations keep the brackets of an IPv6 literal.
            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }

            let scheme = url.scheme?.lowercased()
            let isSecure = scheme == "https" || scheme == "wss" || Cookie.isLoopback(host)

            let path = url.path.isEmpty ? "/" : url.path
            return .init(host: host, path: path, isSecure: isSecure)
        }
    }
}
