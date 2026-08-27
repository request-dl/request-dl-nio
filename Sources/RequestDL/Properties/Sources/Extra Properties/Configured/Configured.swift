//
// See LICENSE for this package's licensing information.
//

import Configuration

/// A property that derives declarative request properties from an external configuration source.
///
/// Use `Configured` to drive a request's `BaseURL`, `RequestMethod`, `Timeout`, headers and query
/// parameters from a `ConfigReader` — backed by environment variables, a JSON file, in-memory
/// defaults, or any other `ConfigProvider` — instead of hardcoding them as Swift literals.
///
/// ```swift
/// DataTask {
///     Configured(appConfig)
/// }
/// ```
///
/// `ConfigReader.scoped(to:)` lets multiple endpoints share one reader under different key prefixes:
///
/// ```swift
/// Configured(appConfig.scoped(to: "myAPI"))
/// ```
///
/// ## Configuration keys
///
/// - `baseURL` (string, optional): passed to ``BaseURL/init(_:)``.
/// - `method` (string, optional): uppercased and passed to ``RequestMethod/init(_:)``.
/// - `timeout` (int, optional): interpreted as seconds and passed to ``Timeout/init(_:for:)``.
/// - `headers` (string array, optional): each entry is a colon-separated `"Name: Value"` pair,
///   collected into a ``HeaderGroup``.
/// - `queries` (string array, optional): each entry is an equals-separated `"name=value"` pair,
///   collected into a ``QueryGroup``.
/// - `authorization` (scoped, optional): passed to ``Authorization``. Reads `authorization.scheme`
///   (`"basic"` or `"bearer"`); `"basic"` additionally reads `authorization.username` and
///   `authorization.password` (or, absent those, a pre-encoded `authorization.credentials`), while
///   `"bearer"` reads `authorization.token`.
/// - `dnsOverrides` (string array, optional): each entry is a colon-separated `"host:IP"` pair,
///   one ``DNSOverride`` per entry.
/// - `systemProxy` (bool, optional, default: `false`): includes ``SystemProxy`` when `true`.
/// - `proxy` (scoped, optional): passed to ``Proxy``. Reads `proxy.enabled` (default `false`;
///   skipped entirely when not `true`), `proxy.host` (required), `proxy.port` (required for
///   `"http"`, defaults to `1080` for `"socks"`), and `proxy.type` (`"http"` or `"socks"`, default
///   `"http"`). For `"http"` proxies only, also reads `proxy.authorization` (same shape as the
///   top-level `authorization` key) and `proxy.connectHeaders` (string array, colon-separated
///   pairs, sent only on the proxy's `CONNECT` request).
///
/// Every key is read independently and is optional: a missing key simply contributes nothing, the
/// same as any other absent property. An explicit property declared after `Configured` in the same
/// `@PropertyBuilder` block still wins, following the same "last one wins" precedent already
/// established by ``BaseURL`` and ``DNSOverride``.
///
/// - Throws: ``ConfiguredError`` if `authorization.scheme` or `proxy.authorization.scheme` is
///   specified but invalid, if the fields either requires are missing, if `proxy.enabled` is `true`
///   but `proxy.host` is missing or `proxy.type` is unknown, if `proxy.port` is missing for an
///   `"http"` proxy, or if `proxy.authorization`/`proxy.connectHeaders` is specified for a `"socks"`
///   proxy.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct Configured: Property {

    // MARK: - Internal properties

    let reader: ConfigReader

    // MARK: - Inits

    ///
    /// Creates a new `Configured` property backed by the given configuration reader.
    ///
    /// - Parameter reader: The `ConfigReader` used to resolve request properties.
    ///
    public init(_ reader: ConfigReader) {
        self.reader = reader
    }

    // MARK: - Public properties

    public var body: some Property {
        let reader = reader

        return AsyncProperty {
            if let baseURL = reader.string(forKey: "baseURL") {
                BaseURL(baseURL)
            }

            if let method = reader.string(forKey: "method") {
                RequestMethod(HTTPMethod(method.uppercased()))
            }

            if let timeout = reader.int(forKey: "timeout") {
                Timeout(.seconds(Int64(timeout)))
            }

            if let headerPairs = reader.stringArray(forKey: "headers") {
                HeaderGroup(Self.pairs(headerPairs, separatedBy: ":"))
            }

            if let queryPairs = reader.stringArray(forKey: "queries") {
                QueryGroup(Self.pairs(queryPairs, separatedBy: "="))
            }

            if let authorization = try Self.authorization(reader.scoped(to: "authorization")) {
                authorization
            }

            if let dnsOverridePairs = reader.stringArray(forKey: "dnsOverrides") {
                PropertyForEach(Self.pairs(dnsOverridePairs, separatedBy: ":"), id: \.key) {
                    DNSOverride($0.value, from: $0.key)
                }
            }

            if reader.bool(forKey: "systemProxy", default: false) {
                SystemProxy()
            }

            try Self.proxy(reader.scoped(to: "proxy"))
        }
    }

    // MARK: - Private static methods

    // Returns a type-erased `AnyProperty` rather than `some Property`: the "http" and "socks"
    // branches each resolve to a different specialization of the generic `Proxy<Headers>`, and
    // asking the compiler to unify those through nested result-builder inference (`some Property`
    // over an `if`/`switch` mixing several `Proxy<Headers>` specializations) runs into a type
    // checker limitation. A plain throwing function returning one concrete type sidesteps it.
    private static func proxy(_ reader: ConfigReader) throws -> AnyProperty {
        guard reader.bool(forKey: "enabled", default: false) else {
            return AnyProperty(EmptyProperty())
        }

        guard let host = reader.string(forKey: "host") else {
            throw ConfiguredError(context: .invalidProxyConfiguration)
        }

        let authorization = try Self.proxyAuthorization(reader.scoped(to: "authorization"))
        let connectHeaderPairs = reader.stringArray(forKey: "connectHeaders")

        switch reader.string(forKey: "type", default: "http") {
        case "http":
            guard let port = reader.int(forKey: "port") else {
                throw ConfiguredError(context: .invalidProxyConfiguration)
            }

            return AnyProperty(
                Proxy(host: host, port: port, authorization: authorization) { () -> ProxyConnectHeaders in
                    // Built from `PropertyForEach`/`CustomHeader` rather than `HeaderGroup`:
                    // `Proxy` discovers its `connectHeaders` content by searching for raw
                    // `HeaderNode` leaves, but `HeaderGroup` wraps its headers into its own
                    // opaque leaf node first, so nesting it here would silently resolve to no
                    // headers at all.
                    PropertyForEach(
                        connectHeaderPairs.map { Self.pairs($0, separatedBy: ":") } ?? [:],
                        id: \.key
                    ) {
                        CustomHeader(name: $0.key, value: $0.value)
                    }
                }
            )
        case "socks":
            guard authorization == nil, connectHeaderPairs == nil else {
                throw ConfiguredError(context: .invalidProxyConfiguration)
            }

            return AnyProperty(
                Proxy(
                    host: host,
                    port: reader.int(forKey: "port", default: 1080),
                    connection: .socks
                )
            )
        default:
            throw ConfiguredError(context: .invalidProxyConfiguration)
        }
    }

    // Matches the `Headers` specialization `proxy(_:)` always builds its `connectHeaders` closure
    // with below (a `PropertyForEach` over the parsed pairs, empty when none are configured), so
    // `Proxy<ProxyConnectHeaders>.Authorization` is the same specialization the compiler infers
    // for the call in `proxy(_:)` — keeping `proxyAuthorization`'s return type generic-free.
    private typealias ProxyConnectHeaders = PropertyForEach<[String: String], String, CustomHeader>

    private static func proxyAuthorization(
        _ reader: ConfigReader
    ) throws -> Proxy<ProxyConnectHeaders>.Authorization? {
        guard let scheme = reader.string(forKey: "scheme") else {
            return nil
        }

        switch scheme {
        case "basic":
            if let username = reader.string(forKey: "username"),
                let password = reader.string(forKey: "password")
            {
                return .basic(username: username, password: password)
            } else if let credentials = reader.string(forKey: "credentials") {
                return .basic(credentials: credentials)
            } else {
                throw ConfiguredError(context: .invalidAuthorizationConfiguration)
            }
        case "bearer":
            guard let token = reader.string(forKey: "token") else {
                throw ConfiguredError(context: .invalidAuthorizationConfiguration)
            }
            return .bearer(tokens: token)
        default:
            throw ConfiguredError(context: .invalidAuthorizationConfiguration)
        }
    }

    private static func authorization(_ reader: ConfigReader) throws -> Authorization? {
        guard let scheme = reader.string(forKey: "scheme") else {
            return nil
        }

        switch scheme {
        case "basic":
            if let username = reader.string(forKey: "username"),
                let password = reader.string(forKey: "password")
            {
                return Authorization(username: username, password: password)
            } else if let credentials = reader.string(forKey: "credentials") {
                return Authorization(.basic, token: credentials)
            } else {
                throw ConfiguredError(context: .invalidAuthorizationConfiguration)
            }
        case "bearer":
            guard let token = reader.string(forKey: "token") else {
                throw ConfiguredError(context: .invalidAuthorizationConfiguration)
            }
            return Authorization(.bearer, token: token)
        default:
            throw ConfiguredError(context: .invalidAuthorizationConfiguration)
        }
    }

    private static func pairs(
        _ entries: [String],
        separatedBy separator: Character
    ) -> [String: String] {
        entries.reduce(into: [String: String]()) { result, entry in
            guard let (key, value) = entry.splitOnFirst(separator) else {
                return
            }

            if !key.isEmpty {
                result[key] = value
            }
        }
    }
}

extension StringProtocol {

    fileprivate func splitOnFirst(_ separator: Character) -> (String, String)? {
        guard let separatorIndex = firstIndex(of: separator) else {
            return nil
        }

        return (
            String(self[..<separatorIndex]).trimmingASCIIWhitespace(),
            String(self[index(after: separatorIndex)...]).trimmingASCIIWhitespace()
        )
    }

    fileprivate func trimmingASCIIWhitespace() -> String {
        guard let start = firstIndex(where: { $0 != " " && $0 != "\t" }),
            let end = lastIndex(where: { $0 != " " && $0 != "\t" })
        else {
            return ""
        }

        return String(self[start...end])
    }
}
