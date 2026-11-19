//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

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
/// - Note: Cookies are not saved to disk. `SameSite` is ignored, as in any client that has no
///   notion of a site making the request, and `HttpOnly` cookies are sent like any other.
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
    public init(publicSuffixList: PublicSuffixList? = nil) {
        storage = Internals.CookieStorage(publicSuffixList: publicSuffixList?.list)
    }

    // MARK: - Public methods

    /// Removes every cookie, for example when the user signs out.
    public func removeAll() {
        storage.removeAll()
    }
}
