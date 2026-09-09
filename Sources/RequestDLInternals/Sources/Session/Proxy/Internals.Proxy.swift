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

#if canImport(Darwin)

extension Internals.Proxy {

    /// `URLSessionConfiguration.connectionProxyDictionary`'s legacy CFNetwork keys for this
    /// proxy -- URLSession has no typed proxy API to mirror `HTTPClient.Configuration.Proxy`
    /// with, only this untyped dictionary. String literals rather than the `CFNetwork` constants
    /// (`kCFNetworkProxiesHTTPEnable` etc.) because they are stable, widely relied upon by
    /// networking libraries, and avoid an extra platform-conditional import for three key names.
    ///
    /// `.http` sets both the `HTTP*` and `HTTPS*` key triples, since HTTPS targets are what
    /// actually trigger the `CONNECT` tunnel this proxy exists to build. `.socks` sets the analogous
    /// `SOCKS*` triple -- no separate HTTPS variant exists for SOCKS, one set of keys covers both.
    /// Neither branch sets a `*Version` key: `URLSession` defaults to SOCKS5 on its own (confirmed
    /// by capturing the actual bytes it sends -- a standard SOCKS5 greeting, `05 01 00`, offering
    /// no-authentication -- not assumed from documentation, which doesn't cover this default at
    /// all), and this executor's SOCKS support doesn't need SOCKS4's narrower feature set.
    ///
    /// `.socks` was excluded from `.urlSession` entirely until this mapping existed
    /// (`Internals.ExecutorIncompatibilityReason.proxySOCKSUnderURLSession`, now removed) --
    /// the original analysis called SOCKS via this dictionary "unreliable/undocumented" and
    /// declined to attempt it. That framing didn't hold up once actually tested:
    /// `InternalsSOCKSProxyDictionaryPlatformTests` confirms (with a negative control, not just a
    /// single positive result) that `URLSession` genuinely dials the configured SOCKS address on
    /// both macOS and an iOS Simulator, and `InternalsURLSessionClientSOCKSProxyTests`
    /// (`LocalSOCKSProxy`, a real hand-rolled SOCKS5 server) confirms a full handshake completes
    /// and actually carries traffic end to end.
    ///
    /// Verified working on macOS for non-loopback destinations (confirmed with a real listener
    /// standing in for the proxy) -- see `InternalsProxyDictionaryPlatformTests` for the
    /// up-to-date per-platform picture. **Not**
    /// provable the same way against `127.0.0.1`/`localhost` targets specifically: macOS bypasses
    /// any configured proxy for loopback destinations as a matter of OS policy, independent of
    /// this mapping being correct -- `LocalServer`/`LocalHTTPConnectProxy`-based round trips in
    /// `InternalsURLSessionClientProxyTests` document that gap specifically, they are not
    /// evidence against this mapping.
    package func buildConnectionProxyDictionary() -> [AnyHashable: Any] {
        switch connectionProtocol {
        case .http:
            return [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port,
            ]

        case .socks:
            return [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port,
            ]
        }
    }
}

#endif
