/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient

extension Internals {

    struct Proxy: Sendable, Equatable {

        enum Authorization: Sendable, Hashable {

            case basic(username: String, password: String)
            case basicRawCredentials(String)
            case bearer(tokens: String)

            func build() -> HTTPClient.Authorization {
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

        enum ConnectionProtocol: Sendable, Hashable {
            case http
            case socks
        }

        let host: String
        let port: Int
        let connectionProtocol: ConnectionProtocol
        let authorization: Authorization?

        init(
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

        func build() -> HTTPClient.Configuration.Proxy {
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
