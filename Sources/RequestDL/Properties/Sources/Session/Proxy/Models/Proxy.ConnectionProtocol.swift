/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Proxy {

    /// An enumeration representing the type of connection protocol used by the proxy server.
    public enum ConnectionProtocol: Sendable {

        /// Specifies an HTTP proxy connection.
        case http

        /// Specifies a SOCKS proxy connection.
        case socks

        func build() -> Internals.Proxy.ConnectionProtocol {
            switch self {
            case .http:
                return .http
            case .socks:
                return .socks
            }
        }
    }
}
