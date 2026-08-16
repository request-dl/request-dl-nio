//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient

extension Internals {

    package struct Proxy: Sendable, Hashable {

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

        package init(
            host: String,
            port: Int,
            connection connectionProtocol: ConnectionProtocol,
            authorization: Authorization?
        ) {
            self.host = host
            self.port = port
            self.connectionProtocol = connectionProtocol
            self.authorization = authorization
        }

        package func build() -> HTTPClient.Configuration.Proxy {
            switch connectionProtocol {
            case .http:
                if let authorization {
                    return .server(
                        host: host,
                        port: port,
                        authorization: authorization.build()
                    )
                } else {
                    return .server(host: host, port: port)
                }
            case .socks:
                return .socksServer(host: host, port: port)
            }
        }
    }
}
