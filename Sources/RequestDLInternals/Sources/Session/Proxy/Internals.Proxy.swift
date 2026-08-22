//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOHTTP1

extension Internals {

    package struct Proxy: Sendable {

        package enum Authorization: Sendable, Hashable {

            case basic(username: String, password: String)
            case basicRawCredentials(String)
            case bearer(tokens: String)

            package func build() -> HTTPClient.Authorization {
                switch self {
                case .basic(let username, let password):
                    return .basic(username: username, password: password)
                case .basicRawCredentials(let credentials):
                    return .basic(credentials: credentials)
                case .bearer(let tokens):
                    return .bearer(tokens: tokens)
                }
            }
        }

        package enum ConnectionProtocol: Sendable, Hashable {
            case http
            case socks
        }

        package let host: String
        package let port: Int
        package let connectionProtocol: ConnectionProtocol
        package let authorization: Authorization?

        /// Extra headers sent only on the HTTP `CONNECT` request to an `.http` proxy.
        ///
        /// Ignored for `.socks`, which has no `CONNECT` phase. Excluded from `Hashable`, same as
        /// upstream's own `HTTPClient.Configuration.Proxy` — `NIOHTTP1.HTTPHeaders` isn't `Hashable`.
        package let connectHeaders: HTTPHeaders

        package init(
            host: String,
            port: Int,
            connection connectionProtocol: ConnectionProtocol,
            authorization: Authorization?,
            connectHeaders: HTTPHeaders = [:]
        ) {
            self.host = host
            self.port = port
            self.connectionProtocol = connectionProtocol
            self.authorization = authorization
            self.connectHeaders = connectHeaders
        }

        package func build() -> HTTPClient.Configuration.Proxy {
            switch connectionProtocol {
            case .http:
                return .server(
                    host: host,
                    port: port,
                    authorization: authorization?.build(),
                    connectHeaders: connectHeaders
                )
            case .socks:
                return .socksServer(host: host, port: port)
            }
        }
    }
}

// MARK: - Hashable

extension Internals.Proxy: Hashable {

    package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.host == rhs.host
            && lhs.port == rhs.port
            && lhs.connectionProtocol == rhs.connectionProtocol
            && lhs.authorization == rhs.authorization
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(port)
        hasher.combine(connectionProtocol)
        hasher.combine(authorization)
    }
}
