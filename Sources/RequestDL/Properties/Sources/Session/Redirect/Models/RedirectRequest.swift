//
// See LICENSE for this package's licensing information.
//

/// The request a ``RedirectStrategy`` is asked to decide on, and the request it can return to
/// follow the redirect with.
///
/// Already carries the standard rewrite rules a redirect implies -- method downgraded to `GET`
/// on a `303` (or a `301`/`302` response to a `POST`), and `Authorization`/`Cookie`/`Origin`/
/// `Proxy-Authorization` stripped when ``url`` no longer shares the original request's origin
/// (scheme, host, and port). A strategy only needs to make further adjustments on top of that,
/// not reimplement those rules from scratch.
public struct RedirectRequest: Sendable {

    // MARK: - Public properties

    /// The URL this request would be sent to.
    public var url: String

    /// The HTTP method this request would use.
    public var method: String

    /// The headers this request would carry.
    public var headers: HTTPHeaders

    /// Whether this request carries a body.
    ///
    /// Read-only: which requests carry a body, and which don't, is already decided by the
    /// redirect rewrite rules (e.g. a `303` drops it) before a ``RedirectStrategy`` ever sees
    /// this value -- there is no supported way to attach or remove a body from here.
    public let hasBody: Bool

    // MARK: - Inits

    ///
    /// Initializes a new redirect request.
    ///
    /// - Parameters:
    ///    - url: The URL this request would be sent to.
    ///    - method: The HTTP method this request would use.
    ///    - headers: The headers this request would carry.
    ///    - hasBody: Whether this request carries a body.
    ///
    public init(
        url: String,
        method: String,
        headers: HTTPHeaders,
        hasBody: Bool
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.hasBody = hasBody
    }
}
