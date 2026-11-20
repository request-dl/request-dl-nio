//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

///
/// `ProxyAuthorization` is a struct that defines the authorization credentials required to connect to a proxy server.
/// This configuration is typically used in conjunction with HTTP or HTTPS proxies.
///
/// You can create an instance of `ProxyAuthorization` using one of its static methods, like `.basic`.
///
/// ```swift
/// let auth = ProxyAuthorization.basic(username: "myuser", password: "mypass")
/// ```
///
/// In the example below, a request is made using an HTTP proxy with basic authentication.
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     Proxy(
///         host: "my-proxy.com",
///         port: 8080,
///         authorization: .basic(username: "user", password: "pass")
///     )
/// }
/// ```
/// A SOCKS5 proxy takes the same user name and password with
/// ``Proxy/init(host:port:connection:authorization:)``:
///
/// ```swift
/// Proxy(
///     host: "socks-proxy.com",
///     port: 1080,
///     connection: .socks,
///     authorization: .basic(username: "user", password: "pass")
/// )
/// ```
///
/// For SOCKS5 the user name and the password are the ones of RFC 1929, not an HTTP header: only
/// ``basic(username:password:)`` is accepted, and ``basic(credentials:)`` and
/// ``bearer(tokens:)`` are refused with a ``ProxyAuthorizationError``. See ``Proxy`` for the
/// limits and for what is sent on the wire.
///
public struct ProxyAuthorization: Sendable {

    private let authorization: Internals.Proxy.Authorization

    ///
    /// Creates an authorization instance using the HTTP Basic Authentication scheme with a username and password.
    ///
    /// - Parameters:
    ///    - username: The username for the proxy authentication.
    ///    - password: The password for the proxy authentication.
    ///
    /// - Returns: A new instance of `ProxyAuthorization`.
    ///
    public static func basic(username: String, password: String) -> Self {
        .init(authorization: .basic(username: username, password: password))
    }

    ///
    /// Creates an authorization instance using a raw credentials string for the HTTP Basic Authentication scheme.
    ///
    /// - Parameters:
    ///    - credentials: The raw credentials string, typically a base64-encoded "username:password".
    ///
    /// - Returns: A new instance of `ProxyAuthorization`.
    ///
    public static func basic(credentials: String) -> Self {
        .init(authorization: .basicRawCredentials(credentials))
    }

    ///
    /// Creates an authorization instance using the HTTP Bearer Authentication scheme.
    ///
    /// - Parameters:
    ///    - tokens: The token string used for the proxy authentication.
    ///
    /// - Returns: A new instance of `ProxyAuthorization`.
    ///
    public static func bearer(tokens: String) -> Self {
        .init(authorization: .bearer(tokens: tokens))
    }

    /// The authorization in the shape a proxy of `connectionProtocol` takes.
    ///
    /// For SOCKS that is `.socks(username:password:)`, made from `.basic(username:password:)`
    /// only; the sizes RFC 1929 allows are checked here too, so the failure is the request's
    /// and not a connection's.
    func build(for connectionProtocol: Internals.Proxy.ConnectionProtocol) throws -> Internals.Proxy.Authorization {
        let resolved: Internals.Proxy.Authorization

        switch (connectionProtocol, authorization) {
        case (.socks, .basic(let username, let password)):
            resolved = .socks(username: username, password: password)
        default:
            resolved = authorization
        }

        do {
            try resolved.validate(for: connectionProtocol)
        } catch let mismatch as Internals.Proxy.Authorization.Mismatch {
            throw ProxyAuthorizationError(mismatch)
        }

        return resolved
    }
}
