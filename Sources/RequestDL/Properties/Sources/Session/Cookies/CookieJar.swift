//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A store of cookies that a ``Session`` fills from the `Set-Cookie` headers of its responses and
/// reads from to set the `Cookie` header of its requests.
///
/// Cookies are opt-in and belong to you: a session has none until you give it a jar, and a jar is
/// the object you create, keep, share between sessions, or throw away. Nothing is stored for a
/// request whose session has no jar.
///
/// ```swift
/// let jar = CookieJar()
///
/// struct MyAppConfiguration: Property {
///     let jar: CookieJar
///
///     var body: some Property {
///         Session("my-app")
///             .cookieJar(jar)
///     }
/// }
/// ```
///
/// A jar follows RFC 6265: a cookie set by a response is sent back to the hosts and paths it
/// applies to, until it expires, over HTTPS when it is `Secure`, and including through the
/// redirects a request follows, where the cookies each hop sets are in time for the next one.
///
/// - Important: A request that sets a `Cookie` header itself keeps it, and is not given the jar's
///   cookies. The jar still stores what its responses set. A jar does not make a ``DataCache``
///   private to it: see <doc:Using-Cookies>.
///
/// Read what a jar holds with ``cookies`` and ``cookies(for:)``, add one with ``insert(_:)``, remove
/// some with ``remove(name:domain:path:)``, ``remove(_:)``, ``removeAll(forHost:includingSubdomains:)``
/// or ``removeAll()``, and keep a jar across launches with ``snapshot(includingSessionCookies:)``
/// and ``init(restoring:publicSuffixList:)``, and find out when it changes with ``changes``. All of them are safe to call from any thread, while
/// requests are using the jar.
///
/// - Note: Cookies are not saved by RequestDL: a snapshot is yours to keep, and to protect (see
///   <doc:Using-Cookies>). `SameSite` is ignored, as in any client that has no notion of a site
///   making the request, and `HttpOnly` cookies are sent like any other.
public final class CookieJar: Sendable {

    // MARK: - Internal properties

    let storage: Internals.CookieStorage

    // MARK: - Inits

    /// Creates an empty jar.
    ///
    /// - Parameter publicSuffixList: The list the jar consults to refuse a cookie whose `Domain`
    ///   is a public suffix, such as `co.uk`, which would otherwise be sent to every site below
    ///   it. The jar refuses a `Domain` that is a single label (`com`) with a list or without
    ///   one; without a list, a multi-label suffix like `co.uk` gets through.
    ///
    ///   Pass a list whenever the jar talks to hosts you do not control. Without one, a tenant of
    ///   a shared hosting platform can plant a cookie on all the others: `attacker.github.io` may
    ///   set `Domain=github.io`, and the jar sends that cookie to every other `*.github.io` it
    ///   visits. The same goes for `*.herokuapp.com`, `*.vercel.app`, `*.netlify.app`,
    ///   `*.pages.dev`, `*.azurewebsites.net`, and S3 buckets under `*.s3.amazonaws.com`. A list
    ///   has them (its private section); see <doc:Using-Cookies>.
    public init(publicSuffixList: PublicSuffixList? = nil) {
        storage = Internals.CookieStorage(publicSuffixList: publicSuffixList?.list)
    }

    /// Creates a jar that holds the cookies of a snapshot.
    ///
    /// The cookies are checked as ``restore(_:)`` checks them, and the ones that fail are left out.
    ///
    /// - Parameters:
    ///   - snapshot: What ``snapshot(includingSessionCookies:)`` returned, possibly in another launch.
    ///   - publicSuffixList: See ``init(publicSuffixList:)``.
    public convenience init(restoring snapshot: Snapshot, publicSuffixList: PublicSuffixList? = nil) {
        self.init(publicSuffixList: publicSuffixList)
        restore(snapshot)
    }

    // MARK: - Public properties

    /// Every cookie that has not expired, in the order the jar first stored them.
    ///
    /// A copy: it does not change when the jar does. Reading it is not a use of the cookies and does
    /// not change which one the jar evicts first when it is full.
    public var cookies: [Cookie] {
        storage.snapshot().map(Cookie.init)
    }

    /// A stream that gets an element each time what the jar holds changes: a response set or deleted
    /// a cookie, or you inserted, removed or restored some, or the jar's limits evicted one. Use it
    /// to save a ``snapshot(includingSessionCookies:)`` when something changed.
    ///
    /// ```swift
    /// let changes = jar.changes
    /// Task {
    ///     for await _ in changes {
    ///         try save(jar.snapshot())
    ///     }
    /// }
    /// ```
    ///
    /// An element says that the jar changed, not what changed or how many times: changes that
    /// happen while you are busy are merged into one, so read the jar again (``cookies`` or
    /// ``snapshot(includingSessionCookies:)``) when you get one, and you see every change that
    /// happened before. It carries no cookie, so it cannot leak one.
    ///
    /// Every read of this property is a new stream, and each is registered when you read it, not when
    /// you start iterating: take it before you read the jar to not miss a change in between. A
    /// stream ends when the jar is deallocated, and stops being tracked when you cancel it or stop
    /// iterating.
    ///
    /// These are not changes: a cookie expiring (nothing happens at that instant; it stops being
    /// listed), a cookie being sent, a response that sets a cookie with the same value, flags and
    /// `Expires` it already has, and a ``removeAll()`` of an empty jar.
    ///
    /// A response that renews a `Max-Age` *is* a change: the expiry it computes is later every
    /// time, and a new expiry is something a snapshot would have to save. A server with sliding
    /// sessions (`Set-Cookie: sid=...; Max-Age=3600` on every response) therefore produces an
    /// element per response. Do not write to disk or to the Keychain on every one: wait a moment
    /// first, and merge the elements that arrive in the meantime.
    public var changes: AsyncStream<Void> {
        storage.changes()
    }

    // MARK: - Public methods

    /// The cookies a request to `url` would be sent, in the order they would be sent: longer paths
    /// first, then the ones created earlier.
    ///
    /// It applies the rules the `Cookie` header does: the host, the path, `Secure` (over HTTPS, or
    /// to a loopback address), and expiry. `HttpOnly` cookies are included. Like ``cookies``, it
    /// is a copy, and reading it is not a use of the cookies.
    ///
    /// The `Cookie` header of a request has at most 8000 bytes, and so does this list: when the
    /// cookies that match do not fit, the ones with the shortest paths are left out of both and,
    /// among equal paths, the oldest, so a cookie that was just set is not the one that goes.
    ///
    /// - Parameter url: The URL of the request. One without a host has no cookies.
    public func cookies(for url: URL) -> [Cookie] {
        storage.cookies(for: url).map(Cookie.init)
    }

    /// Stores a cookie, as if a response had set it.
    ///
    /// A cookie with the same name, domain, path and host-only flag is replaced, and keeps the
    /// ``Cookie/creation`` of the one it replaces. A cookie that has already expired deletes the one it
    /// would have replaced and is not stored. A domain over its 50 cookies, or the jar over its
    /// 3000, evicts the least recently used.
    ///
    /// The cookie must pass the checks a received one does: no control character, name and value
    /// of 4096 bytes at most, the `__Secure-` and `__Host-` rules, and, when it is not host-only,
    /// a domain that is not a single label or a public suffix of the jar's ``PublicSuffixList``.
    /// It has no response to come from, so these are left out:
    ///
    /// - that its domain covers the host that sent it: the domain you give is its origin;
    /// - that a `Secure` cookie came over HTTPS: you may insert one, and it is still only sent over
    ///   HTTPS;
    /// - that plaintext cannot shadow a `Secure` cookie, and the limit of 50 cookies per response.
    ///
    /// And these are stricter, because the grammar of a `Set-Cookie` header enforced them for a
    /// received cookie: a name with `;` or `=`, a value with `;` (it would put a second cookie in the
    /// `Cookie` header), blanks around either, and a path that does not start with `/` (there is
    /// no request to take a default from) are refused.
    ///
    /// - Parameter cookie: The cookie to store. Its domain is normalized first.
    /// - Throws: ``CookieJarError``, and the jar is left as it was.
    public func insert(_ cookie: Cookie) throws {
        do {
            try storage.insert(cookie.internalCookie)
        } catch {
            throw CookieJarError(error)
        }
    }

    /// Removes the cookies with this name, domain and path, whether they are host-only or not.
    ///
    /// - Parameters:
    ///   - name: The name of the cookie.
    ///   - domain: Its domain. It is normalized the way ``insert(_:)`` does.
    ///   - path: Its path.
    /// - Returns: Whether a cookie was removed.
    @discardableResult
    public func remove(name: String, domain: String, path: String) -> Bool {
        storage.remove(name: name, domain: domain, path: path)
    }

    /// Removes the cookie that has the name, domain, path and host-only flag of `cookie`.
    ///
    /// - Returns: Whether a cookie was removed.
    @discardableResult
    public func remove(_ cookie: Cookie) -> Bool {
        storage.remove(cookie.internalCookie)
    }

    /// Removes the cookies a request to `host` is sent, whatever their path and `Secure` flag: the host-only
    /// cookies of `host` itself and the cookies of a domain `host` belongs to. A cookie set for
    /// `example.com` is one of `api.example.com` too, so clearing `api.example.com` removes it.
    ///
    /// - Parameters:
    ///   - host: A host name or an IP address, not a URL. Unicode names are compared in Punycode.
    ///   - includingSubdomains: Whether to remove the cookies of the hosts below `host` as well,
    ///     such as the host-only cookies of `api.example.com` when clearing `example.com`. An IP address
    ///     has none.
    public func removeAll(forHost host: String, includingSubdomains: Bool = false) {
        storage.removeAll(forHost: host, includingSubdomains: includingSubdomains)
    }

    /// Removes every cookie, for example when the user signs out.
    public func removeAll() {
        storage.removeAll()
    }

    /// What the jar holds now, to keep and give back to a jar later.
    ///
    /// - Parameter includingSessionCookies: Whether to include the cookies that have no expiry. A
    ///   session cookie is one the server asked a client to drop when its session ends, and a
    ///   snapshot that keeps it makes it last until the server's own timeout: leave it out unless
    ///   you know that is what you want.
    /// - Returns: The cookies that have not expired. Keep it as you would a password: see
    ///   ``Snapshot``.
    public func snapshot(includingSessionCookies: Bool = false) -> Snapshot {
        Snapshot(
            cookies: storage.snapshot()
                .filter { includingSessionCookies || $0.expires != nil }
                .map(Cookie.init)
        )
    }

    /// Adds the cookies of a snapshot to the jar.
    ///
    /// Each cookie is checked as ``insert(_:)`` checks it, with this jar's public suffix list, and
    /// one that fails is skipped: a snapshot written under another list, or edited, cannot bring in
    /// what the jar would refuse. Unlike ``insert(_:)`` it never deletes (an expired cookie is
    /// skipped) and never replaces: a cookie the jar already holds is newer than one that was kept.
    /// Call ``removeAll()`` first for the other behavior. Only the first 3000 cookies of a
    /// snapshot are considered, and the per-domain limit applies.
    ///
    /// - Parameter snapshot: What ``snapshot(includingSessionCookies:)`` returned.
    /// - Returns: How many cookies of the snapshot were not added, for any of those reasons.
    @discardableResult
    public func restore(_ snapshot: Snapshot) -> Int {
        storage.restore(snapshot.cookies.map(\.internalCookie))
    }
}
