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
///         host: "socks-proxy.com",
///         port: 1080,
///         authorization: .basic(username: "user", password: "pass")
///     )
/// }
/// ```
///
/// A HTTP proxy can also carry extra headers on its `CONNECT` request — sent only while
/// establishing the tunnel, never on the request the tunnel then carries — by composing them
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
                connectHeaders: connectHeaders.build()
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
    let authorization: Authorization?
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
    public init(host: String, port: Int, authorization: Authorization) where Headers == EmptyProperty {
        self.host = host
        self.port = port
        self.connectionProtocol = .http
        self.authorization = authorization
        self.connectHeaders = EmptyProperty()
    }

    ///
    /// Initializes a new instance of `Proxy` without authorization credentials.
    ///
    /// > Warning: SOCKS currently not available with authorization.
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
        authorization: Authorization? = nil,
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

        return .leaf(
            Node(
                host: property.host,
                port: property.port,
                connectionProtocol: property.connectionProtocol.build(),
                authorization: property.authorization?.build(),
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
