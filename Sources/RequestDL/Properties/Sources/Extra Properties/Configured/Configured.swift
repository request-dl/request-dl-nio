//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Configuration
import Crypto
import NIOSSL

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
/// - `baseURL` (string, optional): passed to ``FlexibleURL/init(_:)`` — not ``BaseURL``, since
///   `FlexibleURL` already covers everything a bare host would (a complete `"scheme://host/..."`
///   value sets the base URL, same as `BaseURL`) while also accepting a relative value (e.g.
///   `"/users/123"`, appended to whatever base URL is otherwise in effect) or a query-only value
///   (e.g. `"?active=true"`) in the same field, the same trade-offs `FlexibleURL` documents on its
///   own. A bare host with no scheme (e.g. `"example.com"`) is **not** recognized as a host here —
///   it has no `://`, so `FlexibleURL` reads it as a relative path instead; write
///   `"https://example.com"` for the base URL case.
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
/// - `urlOverrides` (string array, optional): each entry is a `"origin|destination"` pair — both
///   full `"scheme://host[/path]"` strings, so `:`/`/` couldn't serve as the separator the way
///   they do for `dnsOverrides`/`headers` — collected into a single ``URLOverride``.
/// - `systemProxy` (bool, optional, default: `false`): includes ``SystemProxy`` when `true`.
/// - `proxy` (scoped, optional): passed to ``Proxy``. Reads `proxy.enabled` (default `false`;
///   skipped entirely when not `true`), `proxy.host` (required), `proxy.port` (required for
///   `"http"`, defaults to `1080` for `"socks"`), and `proxy.type` (`"http"` or `"socks"`, default
///   `"http"`). For `"http"` proxies only, also reads `proxy.authorization` (same shape as the
///   top-level `authorization` key) and `proxy.connectHeaders` (string array, colon-separated
///   pairs, sent only on the proxy's `CONNECT` request).
/// - `cachePolicy` (string, optional): `"memory"`, `"disk"`, or `"all"`, passed to
///   ``Property/cachePolicy(_:)``.
/// - `cacheStrategy` (string, optional): `"ignoreCachedData"`, `"reloadAndValidateCachedData"`,
///   `"returnCachedDataElseLoad"`, or `"useCachedDataOnly"` — the ``CacheStrategy`` case names
///   verbatim — passed to ``Property/cacheStrategy(_:)``.
/// - `secureConnection` (scoped, optional): reads `secureConnection.trustRoots`,
///   `secureConnection.additionalTrustRoots`, and `secureConnection.certificates` (each a string
///   path to a `PEM` file, passed to ``TrustRoots``, ``AdditionalTrustRoots``, and ``Certificates``
///   respectively — none of these require nesting inside a `SecureConnection`, so each is included
///   independently); `secureConnection.privateKey` (scoped: `.file` required, `.format`
///   (`"pem"`/`"der"`, default `"pem"`), `.password` optional, treated as secret) passed to
///   ``PrivateKey``; `secureConnection.tlsMinimumVersion`/`secureConnection.tlsMaximumVersion`
///   (`"1.0"`/`"1.1"`/`"1.2"`/`"1.3"`), passed to ``SecureConnection/version(minimum:)``/
///   ``SecureConnection/version(maximum:)`` — these two, unlike the rest, do require a
///   `SecureConnection` wrapper, since they configure `SecureConnection` itself rather than a
///   certificate; and `secureConnection.spkiPinning` (scoped, optional, present only when
///   `secureConnection.spkiPinning.pins` is set), passed to ``SPKIPinning``/``SPKIHash``. Reads
///   `secureConnection.spkiPinning.pins` (string array, required, non-empty — each entry a
///   Base64-encoded SHA-256 SPKI digest) and `secureConnection.spkiPinning.policy` (`"strict"` or
///   `"audit"`, default `"strict"`). Only SHA-256 pins are supported through `Configured`; use
///   ``SPKIHash/init(_:algorithm:)`` directly for SHA-384/SHA-512 pins.
/// - `redirect` (scoped, optional): passed to ``Session``. Reads `redirect.mode` (`"follow"` or
///   `"disallow"`; absent entirely, the key contributes nothing rather than assuming either).
///   `"follow"` additionally reads `redirect.maxRedirects` (int, default `5`) and
///   `redirect.allowCycles` (bool, default `false`), passed to
///   ``Session/enableRedirectFollow(max:allowCycles:)``; `"disallow"` is passed to
///   ``Session/disableRedirect()``.
/// - `maximumConnectionsPerHost` (int, optional): passed to
///   ``Session/maximumConnectionsPerHost(_:)``.
/// - `maximumConcurrentConnections` (int, optional): passed to
///   ``Session/maximumConcurrentConnections(_:)``. Both are read independently and, when either
///   is present, chained onto the same ``Session`` value — same as declaring
///   `Session().maximumConnectionsPerHost(x).maximumConcurrentConnections(y)` directly.
///
/// Every key is read independently and is optional: a missing key simply contributes nothing, the
/// same as any other absent property. An explicit property declared after `Configured` in the same
/// `@PropertyBuilder` block still wins, following the same "last one wins" precedent already
/// established by ``BaseURL`` and ``DNSOverride``.
///
/// - Throws: ``ConfiguredError`` if `authorization.scheme` or `proxy.authorization.scheme` is
///   specified but invalid, if the fields the specified scheme requires are missing, if
///   `proxy.enabled` is `true`
///   but `proxy.host` is missing or `proxy.type` is unknown, if `proxy.port` is missing for an
///   `"http"` proxy, if `proxy.authorization`/`proxy.connectHeaders` is specified for a `"socks"`
///   proxy, if `cachePolicy`/`cacheStrategy` is specified but is none of the recognized values, if
///   `secureConnection.privateKey.format` is specified but is neither `"pem"` nor `"der"`, if
///   `secureConnection.tlsMinimumVersion`/`secureConnection.tlsMaximumVersion` is specified but is
///   none of the recognized values, if `secureConnection.spkiPinning.pins` is specified but empty
///   or `secureConnection.spkiPinning.policy` is specified but is neither `"strict"` nor `"audit"`,
///   or if `redirect.mode` is specified but is neither `"follow"` nor `"disallow"`.
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
                FlexibleURL(baseURL)
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

            if let urlOverridePairs = reader.stringArray(forKey: "urlOverrides") {
                URLOverride(Self.pairs(urlOverridePairs, separatedBy: "|"))
            }

            if reader.bool(forKey: "systemProxy", default: false) {
                SystemProxy()
            }

            try Self.proxy(reader.scoped(to: "proxy"))

            if let cachePolicy = reader.string(forKey: "cachePolicy") {
                EmptyProperty().cachePolicy(try Self.cachePolicy(cachePolicy))
            }

            if let cacheStrategy = reader.string(forKey: "cacheStrategy") {
                EmptyProperty().cacheStrategy(try Self.cacheStrategy(cacheStrategy))
            }

            let secureConnectionReader = reader.scoped(to: "secureConnection")

            if let trustRootsFile = secureConnectionReader.string(forKey: "trustRoots") {
                TrustRoots(trustRootsFile)
            }

            if let additionalTrustRootsFile = secureConnectionReader.string(forKey: "additionalTrustRoots") {
                AdditionalTrustRoots(additionalTrustRootsFile)
            }

            if let certificatesFile = secureConnectionReader.string(forKey: "certificates") {
                Certificates(certificatesFile)
            }

            if let spkiPinning = try Self.spkiPinning(secureConnectionReader.scoped(to: "spkiPinning")) {
                spkiPinning
            }

            if let privateKey = try Self.privateKey(secureConnectionReader.scoped(to: "privateKey")) {
                privateKey
            }

            if let secureConnection = try Self.secureConnectionVersion(secureConnectionReader) {
                secureConnection
            }

            if let redirect = try Self.redirect(reader.scoped(to: "redirect")) {
                redirect
            }

            if let connectionLimits = Self.connectionLimits(reader) {
                connectionLimits
            }
        }
    }

    // MARK: - Private static methods

    private static func connectionLimits(_ reader: ConfigReader) -> Session? {
        let maximumConnectionsPerHost = reader.int(forKey: "maximumConnectionsPerHost")
        let maximumConcurrentConnections = reader.int(forKey: "maximumConcurrentConnections")

        guard maximumConnectionsPerHost != nil || maximumConcurrentConnections != nil else {
            return nil
        }

        var session = Session()

        if let maximumConnectionsPerHost {
            session = session.maximumConnectionsPerHost(maximumConnectionsPerHost)
        }

        if let maximumConcurrentConnections {
            session = session.maximumConcurrentConnections(maximumConcurrentConnections)
        }

        return session
    }

    private static func redirect(_ reader: ConfigReader) throws -> Session? {
        guard let mode = reader.string(forKey: "mode") else {
            return nil
        }

        switch mode {
        case "follow":
            return Session().enableRedirectFollow(
                max: reader.int(forKey: "maxRedirects", default: 5),
                allowCycles: reader.bool(forKey: "allowCycles", default: false)
            )
        case "disallow":
            return Session().disableRedirect()
        default:
            throw ConfiguredError(context: .invalidRedirectConfiguration)
        }
    }

    private static func spkiPinning(
        _ reader: ConfigReader
    ) throws -> SPKIPinning<PropertyForEach<[String], String, SPKIHash<SHA256>>>? {
        guard let pins = reader.stringArray(forKey: "pins") else {
            return nil
        }

        guard !pins.isEmpty else {
            throw ConfiguredError(context: .invalidSecureConnectionConfiguration)
        }

        let policy = try Self.spkiPinningPolicy(reader.string(forKey: "policy", default: "strict"))

        return SPKIPinning(policy: policy) {
            PropertyForEach(pins, id: \.self) {
                SPKIHash($0)
            }
        }
    }

    private static func spkiPinningPolicy(_ value: String) throws -> SPKIPinningPolicy {
        switch value {
        case "strict":
            return .strict
        case "audit":
            return .audit
        default:
            throw ConfiguredError(context: .invalidSecureConnectionConfiguration)
        }
    }

    private static func privateKey(_ reader: ConfigReader) throws -> PrivateKey? {
        guard let file = reader.string(forKey: "file") else {
            return nil
        }

        let format = try Self.certificateFormat(reader.string(forKey: "format", default: "pem"))

        if let password = reader.string(forKey: "password", isSecret: true) {
            return PrivateKey(file, format: format, password: NIOSSLSecureBytes(password.utf8))
        }

        return PrivateKey(file, format: format)
    }

    private static func secureConnectionVersion(
        _ reader: ConfigReader
    ) throws -> SecureConnection<EmptyProperty>? {
        let minimum = try reader.string(forKey: "tlsMinimumVersion").map(Self.tlsVersion)
        let maximum = try reader.string(forKey: "tlsMaximumVersion").map(Self.tlsVersion)

        guard minimum != nil || maximum != nil else {
            return nil
        }

        var secureConnection = SecureConnection()

        if let minimum {
            secureConnection = secureConnection.version(minimum: minimum)
        }

        if let maximum {
            secureConnection = secureConnection.version(maximum: maximum)
        }

        return secureConnection
    }

    private static func certificateFormat(_ value: String) throws -> Certificate.Format {
        switch value {
        case "pem":
            return .pem
        case "der":
            return .der
        default:
            throw ConfiguredError(context: .invalidSecureConnectionConfiguration)
        }
    }

    private static func tlsVersion(_ value: String) throws -> TLSVersion {
        switch value {
        case "1.0":
            return .v1
        case "1.1":
            return .v1_1
        case "1.2":
            return .v1_2
        case "1.3":
            return .v1_3
        default:
            throw ConfiguredError(context: .invalidSecureConnectionConfiguration)
        }
    }

    private static func cacheStrategy(_ value: String) throws -> CacheStrategy {
        switch value {
        case "ignoreCachedData":
            return .ignoreCachedData
        case "reloadAndValidateCachedData":
            return .reloadAndValidateCachedData
        case "returnCachedDataElseLoad":
            return .returnCachedDataElseLoad
        case "useCachedDataOnly":
            return .useCachedDataOnly
        default:
            throw ConfiguredError(context: .invalidCacheStrategy)
        }
    }

    private static func cachePolicy(_ value: String) throws -> DataCache.Policy.Set {
        switch value {
        case "memory":
            return .memory
        case "disk":
            return .disk
        case "all":
            return .all
        default:
            throw ConfiguredError(context: .invalidCachePolicy)
        }
    }

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

    private typealias ProxyConnectHeaders = PropertyForEach<[String: String], String, CustomHeader>

    private static func proxyAuthorization(
        _ reader: ConfigReader
    ) throws -> ProxyAuthorization? {
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
