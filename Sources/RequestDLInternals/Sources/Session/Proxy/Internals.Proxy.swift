//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    package struct Proxy: Sendable {

        /// The credentials of a proxy, in the shape the proxy's protocol takes them.
        ///
        /// `.basic`, `.basicRawCredentials` and `.bearer` are HTTP `Proxy-Authorization` header
        /// shapes, for an `.http` proxy. `.socks` is what a `.socks` proxy takes: the
        /// username/password sub-negotiation of RFC 1929, which is not a header and has no scheme.
        /// A shape on the other kind of proxy is rejected by ``validate(for:)`` rather than
        /// dropped, so credentials are never silently left unused.
        ///
        /// The secrets of every shape are kept out of `description`, `debugDescription` and the
        /// `Mirror`; `==` and `hash(into:)` still see them (a pooled client is only reusable by
        /// the same credentials).
        package enum Authorization: Sendable, Hashable {

            case basic(username: String, password: String)
            case basicRawCredentials(String)
            case bearer(tokens: String)

            /// SOCKS5 username/password (RFC 1929). The username takes 1...255 bytes and the
            /// password 0...255 bytes, in UTF-8, and the password is sent in clear text.
            case socks(username: String, password: String)

            /// What RFC 1929 allows for the username: its length is one byte on the wire, and
            /// zero is not a username.
            package static let socksUsernameByteCounts = 1...255

            /// What RFC 1929 allows for the password: an empty one is valid.
            package static let socksPasswordByteCounts = 0...255

            /// The longest username or password `URLSession` sends intact: CFNetwork cuts a longer
            /// one at 254 bytes, which RFC 1929 would still accept at 255. Measured, not
            /// documented; see `InternalsURLSessionClientSOCKSAuthenticationTests`.
            package static let urlSessionSOCKSCredentialByteLimit = 254

            /// Why an authorization does not fit the proxy it is configured on.
            package enum Mismatch: Sendable, Hashable {
                /// A SOCKS proxy was given an HTTP header shape (`.basic`, `.basicRawCredentials`,
                /// `.bearer`).
                case httpShapeOnSOCKSProxy
                /// An HTTP proxy was given the SOCKS username/password shape.
                case socksShapeOnHTTPProxy
                case socksUsernameLength(Int)
                case socksPasswordLength(Int)
                /// A NUL byte in the user name or the password. RFC 1929 allows it, but
                /// CFNetwork treats the credentials as C strings and would cut them at it, so
                /// `.urlSession` would authenticate with other credentials than `.nio`.
                case socksCredentialContainsNUL
            }

            /// The username and password to send to a SOCKS proxy; only the `.socks` shape has them.
            ///
            /// `.basic(username:password:)` is deliberately not converted here: the public
            /// `Proxy` converts it when it builds the node, so everything below it sees one
            /// shape per protocol, and an HTTP shape that reaches a SOCKS proxy any other way
            /// is a mistake that is reported (``Mismatch/httpShapeOnSOCKSProxy``), not guessed at.
            package var socksCredentials: (username: String, password: String)? {
                guard case .socks(let username, let password) = self else {
                    return nil
                }

                return (username, password)
            }

            /// Checks that this authorization is usable on a proxy of `connection`, and, on a
            /// SOCKS proxy, that the credentials fit RFC 1929 (and carry no NUL byte, see
            /// ``Mismatch/socksCredentialContainsNUL``).
            package func validate(for connection: ConnectionProtocol) throws {
                switch connection {
                case .http:
                    if case .socks = self {
                        throw Mismatch.socksShapeOnHTTPProxy
                    }

                case .socks:
                    guard let credentials = socksCredentials else {
                        throw Mismatch.httpShapeOnSOCKSProxy
                    }

                    let usernameCount = credentials.username.utf8.count
                    let passwordCount = credentials.password.utf8.count

                    guard Self.socksUsernameByteCounts.contains(usernameCount) else {
                        throw Mismatch.socksUsernameLength(usernameCount)
                    }

                    guard Self.socksPasswordByteCounts.contains(passwordCount) else {
                        throw Mismatch.socksPasswordLength(passwordCount)
                    }

                    guard !credentials.username.utf8.contains(0), !credentials.password.utf8.contains(0) else {
                        throw Mismatch.socksCredentialContainsNUL
                    }
                }
            }

            #if canImport(NIOCore)
            /// The header an `.http` proxy is sent. A `.socks` authorization has none.
            package func build() throws -> HTTPClient.Authorization {
                switch self {
                case .basic(let username, let password):
                    return .basic(username: username, password: password)
                case .basicRawCredentials(let credentials):
                    return .basic(credentials: credentials)
                case .bearer(let tokens):
                    return .bearer(tokens: tokens)
                case .socks:
                    throw Mismatch.socksShapeOnHTTPProxy
                }
            }
            #endif
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
        /// Ignored for `.socks`, which has no `CONNECT` phase. Included in `Hashable` below,
        /// unlike upstream's own `HTTPClient.Configuration.Proxy` (whose `NIOHTTP1.HTTPHeaders`
        /// isn't `Hashable`): this is `Internals.HTTPHeaders`, this package's own portable type,
        /// which is `Hashable`.
        package let connectHeaders: Internals.HTTPHeaders

        package init(
            host: String,
            port: Int,
            connection connectionProtocol: ConnectionProtocol,
            authorization: Authorization?,
            connectHeaders: Internals.HTTPHeaders = [:]
        ) {
            self.host = host
            self.port = port
            self.connectionProtocol = connectionProtocol
            self.authorization = authorization
            self.connectHeaders = connectHeaders
        }

        /// The same proxy when its SOCKS credentials can be sent, and otherwise the proxy without them.
        ///
        /// For what the system decides and not the caller: a proxy found in the environment or
        /// the system settings used to be run without the credentials it carried for SOCKS (they
        /// were dropped), so credentials RFC 1929 cannot carry are still dropped rather than
        /// failing a request that the user did not configure. Reported through `logger`, without
        /// the credentials. An explicit `Proxy` never goes through this: it throws instead.
        package func droppingUnusableSOCKSCredentials(logger: Logger?) -> Internals.Proxy {
            guard connectionProtocol == .socks, let authorization else {
                return self
            }

            do {
                try authorization.validate(for: .socks)
                return self
            } catch let mismatch as Authorization.Mismatch {
                Internals.Log.systemProxySOCKSCredentialsIgnored(mismatch: mismatch)
                    .log(level: .warning, logger: logger)
            } catch {
                // `validate(for:)` only throws `Mismatch`.
            }

            return Internals.Proxy(
                host: host,
                port: port,
                connection: connectionProtocol,
                authorization: nil,
                connectHeaders: connectHeaders
            )
        }

        /// Checks that `authorization` is usable on this proxy's protocol, and in the sizes
        /// SOCKS5 can carry. Throws ``Authorization/Mismatch`` otherwise.
        package func validate() throws {
            try authorization?.validate(for: connectionProtocol)
        }

        #if canImport(NIOCore)
        /// - Throws: ``Authorization/Mismatch`` when `authorization` does not fit the proxy's
        /// protocol, or AsyncHTTPClient's own `HTTPClientError.invalidProxyConfiguration` if it
        /// still rejects the SOCKS credentials.
        package func build() throws -> HTTPClient.Configuration.Proxy {
            try validate()

            switch connectionProtocol {
            case .http:
                return .server(
                    host: host,
                    port: port,
                    authorization: try authorization?.build(),
                    connectHeaders: connectHeaders.build()
                )
            case .socks:
                guard let credentials = authorization?.socksCredentials else {
                    return .socksServer(host: host, port: port)
                }

                return try .socksServer(
                    host: host,
                    port: port,
                    username: credentials.username,
                    password: credentials.password
                )
            }
        }
        #endif
    }
}

// MARK: - Hashable

extension Internals.Proxy: Hashable {

    // `connectHeaders` matters here: `Internals.Session.Configuration.==` uses this as part of
    // `Internals.ClientManager`'s pooled-client cache key. Omitting it would let two sessions
    // whose proxy differs only in CONNECT headers (commonly where proxy-auth secrets, distinct
    // per session, actually live) be treated as interchangeable, sharing (and thereby leaking
    // across sessions) whichever one first built the pooled client.
    package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.host == rhs.host
            && lhs.port == rhs.port
            && lhs.connectionProtocol == rhs.connectionProtocol
            && lhs.authorization == rhs.authorization
            && lhs.connectHeaders == rhs.connectHeaders
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(port)
        hasher.combine(connectionProtocol)
        hasher.combine(authorization)
        hasher.combine(connectHeaders)
    }
}

// MARK: - Secrets

extension Internals.Proxy.Authorization.Mismatch: Error {}

extension Internals.Proxy.Authorization: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    package var description: String {
        switch self {
        case .basic:
            return "Authorization.basic(username: <redacted>, password: <redacted>)"
        case .basicRawCredentials:
            return "Authorization.basicRawCredentials(<redacted>)"
        case .bearer:
            return "Authorization.bearer(<redacted>)"
        case .socks:
            return "Authorization.socks(username: <redacted>, password: <redacted>)"
        }
    }

    package var debugDescription: String {
        description
    }

    package var customMirror: Mirror {
        Mirror(self, children: [(label: String?, value: Any)](), displayStyle: .enum)
    }
}

#if canImport(Darwin)

extension Internals.Proxy {

    /// `URLSessionConfiguration.connectionProxyDictionary`'s legacy CFNetwork keys for this
    /// proxy: URLSession has no typed proxy API to mirror `HTTPClient.Configuration.Proxy`
    /// with, only this untyped dictionary. String literals rather than the `CFNetwork` constants
    /// (`kCFNetworkProxiesHTTPEnable` etc.) because they are stable, widely relied upon by
    /// networking libraries, and avoid an extra platform-conditional import for three key names.
    ///
    /// `.http` sets both the `HTTP*` and `HTTPS*` key triples, since HTTPS targets are what
    /// actually trigger the `CONNECT` tunnel this proxy exists to build. `.socks` sets the analogous
    /// `SOCKS*` triple: no separate HTTPS variant exists for SOCKS, one set of keys covers both.
    ///
    /// Neither branch sets a `*Version` key: `URLSession` defaults to SOCKS5 on its own (confirmed
    /// by capturing the actual bytes it sends: a standard SOCKS5 greeting, `05 01 00`, offering
    /// no-authentication, not assumed from documentation, which doesn't cover this default at
    /// all), and this executor's SOCKS support doesn't need SOCKS4's narrower feature set.
    ///
    /// `.socks` was excluded from `.urlSession` entirely until this mapping existed
    /// (`Internals.ExecutorIncompatibilityReason.proxySOCKSUnderURLSession`, now removed): the
    /// original analysis called SOCKS via this dictionary "unreliable/undocumented" and declined
    /// to attempt it. That framing didn't hold up once actually tested.
    ///
    /// `InternalsSOCKSProxyDictionaryPlatformTests` confirms (with a negative control, not just a
    /// single positive result) that `URLSession` genuinely dials the configured SOCKS address on
    /// both macOS and an iOS Simulator, and `InternalsURLSessionClientSOCKSProxyTests`
    /// (`LocalSOCKSProxy`, a real hand-rolled SOCKS5 server) confirms a full handshake completes
    /// and actually carries traffic end to end.
    ///
    /// Verified working on macOS for non-loopback destinations (confirmed with a real listener
    /// standing in for the proxy); see `InternalsProxyDictionaryPlatformTests` for the
    /// up-to-date per-platform picture.
    ///
    /// **Not** provable the same way against `127.0.0.1`/`localhost` targets specifically: macOS
    /// bypasses any configured proxy for loopback destinations as a matter of OS policy,
    /// independent of this mapping being correct. `LocalServer`/`LocalHTTPConnectProxy`-based
    /// round trips in `InternalsURLSessionClientProxyTests` document that gap specifically; they
    /// are not evidence against this mapping.
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
            var dictionary: [AnyHashable: Any] = [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port,
            ]

            // RFC 1929 username/password. Verified against `LocalSOCKSProxy`
            // (`InternalsURLSessionClientSOCKSAuthenticationTests`): with these two keys
            // `URLSession` offers methods `00 02` in its greeting and sends the credentials, and
            // a wrong password fails at once with `NSPOSIXErrorDomain` 80. Without them the
            // greeting offers `00` only.
            if let credentials = authorization?.socksCredentials {
                dictionary["SOCKSUser"] = credentials.username
                dictionary["SOCKSPassword"] = credentials.password
            }

            return dictionary
        }
    }
}

#endif
