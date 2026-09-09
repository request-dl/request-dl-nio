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

    func build() -> Internals.Proxy.Authorization {
        authorization
    }
}
