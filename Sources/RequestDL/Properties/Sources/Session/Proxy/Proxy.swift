//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// `Proxy` is a struct that defines a proxy configuration for network requests.
///
/// To create an instance of `Proxy`, initialize it with the host, port, connection protocol, and optionally, authorization credentials.
///
/// ```swift
/// Proxy(host: "myproxy.com", port: 8080, connection: .socks)
/// ```
///
/// In the example below, a request is made using a HTTP proxy with authentication.
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     Proxy(
///         host: "http-proxy.com",
///         port: 8080,
///         authorization: .basic(username: "user", password: "pass")
///     )
/// }
/// ```
///
/// ## SOCKS5 with a user name and a password
///
/// A SOCKS5 proxy that requires authentication takes a user name and a password
/// (RFC 1929) through ``init(host:port:connection:authorization:)``, with the same
/// ``ProxyAuthorization/basic(username:password:)`` an HTTP proxy takes:
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     Proxy(
///         host: "socks-proxy.com",
///         port: 1080,
///         connection: .socks,
///         authorization: .basic(username: "user", password: "pass")
///     )
/// }
/// ```
///
/// - The user name takes 1 to 255 bytes and the password 0 to 255 bytes, counted in UTF-8, so an
///   empty password is valid and a non-ASCII one is counted by its encoded size. Neither can
///   contain a NUL character, which `URLSession` would cut the credentials at. Outside of
///   that, resolving the request throws a ``ProxyAuthorizationError`` before anything is sent.
/// - A proxy found by ``SystemProxy`` (the environment, or the system settings) can carry
///   credentials too, and is used with them. Credentials of that kind that SOCKS5 cannot carry
///   (by the limits above) are ignored with a warning in the log, never an error, and the proxy
///   is used without them. The one exception is credentials of 255 bytes, which are within
///   those limits and so are kept, but which `.urlSession` cannot send intact (see the last
///   item): a session that does not name an executor runs such a system proxy on a NIO executor, and
///   one that requires `.urlSession` throws an ``ExecutorRequirementError``.
/// - SOCKS5 authenticates with a user name and a password and nothing else:
///   ``ProxyAuthorization/basic(credentials:)`` and ``ProxyAuthorization/bearer(tokens:)`` are
///   HTTP header values, and are refused with a ``ProxyAuthorizationError``. Nothing is
///   converted from them.
/// - The credentials are sent **in clear text** to the proxy (RFC 1929 has no encryption), so
///   anyone who can read the connection to the proxy can read them; use the proxy only over a
///   network that is trusted, or tunnel to it. The credentials are never part of the request
///   that the tunnel carries.
/// - A proxy that rejects the credentials fails the request at once with a
///   ``ProxyAuthorizationError`` whose reason is
///   ``ProxyAuthorizationError/Reason-swift.enum/socksAuthenticationRejected``, the same on every
///   executor, and it is not retried: sending the same wrong credentials again could only lock the
///   account. That is a proxy that answers with a failure status (RFC 1929 says it must), and, under
///   `.nio` and `.nioTransportServices`, one that closes the connection after receiving the
///   credentials without answering at all, which is taken for the same rejection. The error never
///   carries the credentials. What the executor itself reported, kept as
///   ``ProxyAuthorizationError/underlyingError`` for diagnosis, is `SOCKSError.AuthenticationFailed`
///   (from `NIOSOCKS`, which RequestDL does not re-export) under `.nio` and `.nioTransportServices`,
///   and an `NSError` in `NSPOSIXErrorDomain` with code `EAUTH` (80) under `.urlSession`.
/// - A proxy that does not require authentication simply does not ask for the credentials,
///   which are then not sent.
/// - Under `.urlSession` a user name or password of more than 254 bytes cannot be sent intact:
///   CFNetwork cuts it. Such a session does not run on `.urlSession`; see
///   ``Session/requiredExecutor(_:)`` and ``ExecutorRequirementError``.
///
/// A HTTP proxy can also carry extra headers on its `CONNECT` request (sent only while
/// establishing the tunnel, never on the request the tunnel then carries) by composing them
/// the same way ``RequestDL/Form`` composes per-part headers, with any `Property` that resolves
/// to headers (``RequestDL/CustomHeader``, ``RequestDL/HeaderGroup``, etc):
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     Proxy(host: "proxy.example.com", port: 8080) {
///         CustomHeader(name: "X-Proxy-Token", value: "abc123")
///     }
/// }
/// ```
///
/// > Note: The `Headers` generic parameter represents the type of the `CONNECT` headers
/// composition. If none are needed, the default is `EmptyProperty`.
public struct Proxy<Headers: Property>: Property {

    private struct Node: PropertyNode {

        let host: String
        let port: Int
        let connectionProtocol: Internals.Proxy.ConnectionProtocol
        let authorization: Internals.Proxy.Authorization?
        let connectHeaders: RequestDL.HTTPHeaders

        func make(_ make: inout Make) async throws {
            make.sessionConfiguration.proxy = .init(
                host: host,
                port: port,
                connection: connectionProtocol,
                authorization: authorization,
                connectHeaders: connectHeaders.makeInternalHeaders()
            )
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let host: String
    let port: Int
    let connectionProtocol: ConnectionProtocol
    let authorization: ProxyAuthorization?
    let connectHeaders: Headers

    // MARK: - Inits

    ///
    /// Initializes a new instance of HTTP `Proxy` with authorization credentials.
    ///
    /// - Parameters:
    ///    - host: The hostname or IP address of the proxy server.
    ///    - port: The port number on which the proxy server is listening.
    ///    - authorization: Optional credentials for authenticating with the proxy server.
    ///
    /// - Returns: A new instance of `Proxy`.
    ///
    /// > Note: This initializer is available when `Headers` is `EmptyProperty`.
    ///
    public init(host: String, port: Int, authorization: ProxyAuthorization) where Headers == EmptyProperty {
        self.host = host
        self.port = port
        self.connectionProtocol = .http
        self.authorization = authorization
        self.connectHeaders = EmptyProperty()
    }

    ///
    /// Initializes a new instance of `Proxy` without authorization credentials.
    ///
    /// - Parameters:
    ///    - host: The hostname or IP address of the proxy server.
    ///    - port: The port number on which the proxy server is listening.
    ///    - connectionProtocol: The protocol used by the proxy (e.g., HTTP, HTTPS, SOCKS).
    ///
    /// - Returns: A new instance of `Proxy`.
    ///
    /// > Note: This initializer is available when `Headers` is `EmptyProperty`.
    ///
    public init(
        host: String,
        port: Int,
        connection connectionProtocol: ConnectionProtocol
    ) where Headers == EmptyProperty {
        self.host = host
        self.port = port
        self.connectionProtocol = connectionProtocol
        self.authorization = nil
        self.connectHeaders = EmptyProperty()
    }

    ///
    /// Initializes a new instance of `Proxy` with authorization credentials, for either protocol.
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
    /// For an HTTP proxy this is the same as ``init(host:port:authorization:)``. For a SOCKS
    /// proxy the authorization is the user name and the password of SOCKS5 (RFC 1929):
    /// ``ProxyAuthorization/basic(username:password:)`` is converted to them, and
    /// ``ProxyAuthorization/basic(credentials:)`` and ``ProxyAuthorization/bearer(tokens:)`` are
    /// refused.
    ///
    /// - Parameters:
    ///    - host: The hostname or IP address of the proxy server.
    ///    - port: The port number on which the proxy server is listening.
    ///    - connectionProtocol: The protocol used by the proxy (e.g., HTTP, SOCKS).
    ///    - authorization: The credentials for authenticating with the proxy server.
    ///
    /// - Returns: A new instance of `Proxy`.
    ///
    /// > Important: The user name and the password of a SOCKS5 proxy are sent in clear text.
    ///
    /// - Throws: Resolving the request throws a ``ProxyAuthorizationError`` for a SOCKS proxy
    /// whose authorization is not a user name and a password, whose user name does not have 1
    /// to 255 bytes in UTF-8, or whose password does not have 0 to 255.
    ///
    /// > Note: This initializer is available when `Headers` is `EmptyProperty`.
    ///
    public init(
        host: String,
        port: Int,
        connection connectionProtocol: ConnectionProtocol,
        authorization: ProxyAuthorization
    ) where Headers == EmptyProperty {
        self.host = host
        self.port = port
        self.connectionProtocol = connectionProtocol
        self.authorization = authorization
        self.connectHeaders = EmptyProperty()
    }

    ///
    /// Initializes a new instance of HTTP `Proxy` with extra headers on its `CONNECT` request.
    ///
    /// - Parameters:
    ///    - host: The hostname or IP address of the proxy server.
    ///    - port: The port number on which the proxy server is listening.
    ///    - authorization: Optional credentials for authenticating with the proxy server.
    ///    - connectHeaders: A closure that returns the headers sent only on the `CONNECT`
    ///    request used to establish the tunnel. `host` and `proxy-authorization` are always set
    ///    by the underlying transport and cannot be overridden here.
    ///
    /// - Returns: A new instance of `Proxy`.
    ///
    /// > Note: SOCKS has no `CONNECT` phase, so `connectHeaders` is only reachable through the
    /// HTTP proxy initializers.
    ///
    public init(
        host: String,
        port: Int,
        authorization: ProxyAuthorization? = nil,
        @PropertyBuilder connectHeaders: () -> Headers
    ) {
        self.host = host
        self.port = port
        self.connectionProtocol = .http
        self.authorization = authorization
        self.connectHeaders = connectHeaders()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Proxy>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let connectHeaders = try await connectHeaders(
            property: property,
            inputs: inputs
        )

        let connection = property.connectionProtocol.build()

        return .leaf(
            Node(
                host: property.host,
                port: property.port,
                connectionProtocol: connection,
                authorization: try property.authorization?.build(for: connection),
                connectHeaders: connectHeaders
            )
        )
    }

    // MARK: - Private static methods

    private static func connectHeaders(
        property: _GraphValue<Proxy<Headers>>,
        inputs: _PropertyInputs
    ) async throws -> RequestDL.HTTPHeaders {
        let output = try await Headers._makeProperty(
            property: property.connectHeaders,
            inputs: inputs
        )

        var headers = RequestDL.HTTPHeaders()

        for header in output.node.search(for: HeaderNode.self) {
            header.makeHeadersClosure(&headers)
        }

        return headers
    }
}
