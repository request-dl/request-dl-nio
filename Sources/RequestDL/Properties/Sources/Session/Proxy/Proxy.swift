/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `Proxy` is a struct that defines a proxy configuration for network requests.

 To create an instance of `Proxy`, initialize it with the host, port, connection protocol, and optionally, authorization credentials.

 ```swift
 Proxy(host: "myproxy.com", port: 8080, connection: .socks)
 ```

 In the example below, a request is made using a HTTP proxy with authentication.

 ```swift
 DataTask {
     BaseURL("example.com")
     Proxy(
         host: "socks-proxy.com",
         port: 1080,
         authorization: .basic(username: "user", password: "pass")
     )
 }
 ```
 */
public struct Proxy: Property {

    private struct Node: PropertyNode {

        let host: String
        let port: Int
        let connectionProtocol: Internals.Proxy.ConnectionProtocol
        let authorization: Internals.Proxy.Authorization?

        func make(_ make: inout Make) async throws {
            make.sessionConfiguration.proxy = .init(
                host: host,
                port: port,
                connection: connectionProtocol,
                authorization: authorization
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

    // MARK: - Inits

    /**
     Initializes a new instance of HTTP `Proxy` with authorization credentials.

     - Parameters:
        - host: The hostname or IP address of the proxy server.
        - port: The port number on which the proxy server is listening.
        - authorization: Optional credentials for authenticating with the proxy server.

     - Returns: A new instance of `Proxy`.
     */
    public init(host: String, port: Int, authorization: Authorization) {
        self.host = host
        self.port = port
        self.connectionProtocol = .http
        self.authorization = authorization
    }

    /**
     Initializes a new instance of `Proxy` without authorization credentials.

     > Warning: SOCKS currently not available with authorization.

     - Parameters:
        - host: The hostname or IP address of the proxy server.
        - port: The port number on which the proxy server is listening.
        - connectionProtocol: The protocol used by the proxy (e.g., HTTP, HTTPS, SOCKS).

     - Returns: A new instance of `Proxy`.
     */
    public init(host: String, port: Int, connection connectionProtocol: ConnectionProtocol) {
        self.host = host
        self.port = port
        self.connectionProtocol = connectionProtocol
        self.authorization = nil
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Proxy>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                host: property.host,
                port: property.port,
                connectionProtocol: property.connectionProtocol.build(),
                authorization: property.authorization?.build()
            )
        )
    }
}
