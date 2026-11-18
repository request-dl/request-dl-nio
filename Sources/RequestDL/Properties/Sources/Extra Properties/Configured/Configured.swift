//
// See LICENSE for this package's licensing information.
//

import Configuration
import Crypto

/// A property that derives declarative request properties from an external configuration source.
///
/// Use `Configured` to drive a request's `BaseURL`, `RequestMethod`, `Timeout`, headers and query
/// parameters from a `ConfigReader` (backed by environment variables, a JSON file, in-memory
/// defaults, or any other `ConfigProvider`) instead of hardcoding them as Swift literals.
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
/// - `baseURL` (string, optional): passed to ``FlexibleURL/init(_:)``, not ``BaseURL``, since
///   `FlexibleURL` already covers everything a bare host would (a complete `"scheme://host/..."`
///   value sets the base URL, same as `BaseURL`) while also accepting a relative value (e.g.
///   `"/users/123"`, appended to whatever base URL is otherwise in effect) or a query-only value
///   (e.g. `"?active=true"`) in the same field, the same trade-offs `FlexibleURL` documents on its
///   own. A bare host with no scheme (e.g. `"example.com"`) is **not** recognized as a host here:
///   it has no `://`, so `FlexibleURL` reads it as a relative path instead; write
///   `"https://example.com"` for the base URL case. A user name or a password in the authority
///   (`"https://user:password@example.com"`) is an error: the request would not send it, and it
///   would end up in logs. Use `authorization` instead.
/// - `method` (string, optional): uppercased and passed to ``RequestMethod/init(_:)``.
/// - `timeout` (int, optional): interpreted as seconds and passed to ``Timeout/init(_:for:)``. A
///   negative value is an error, see ``ConfiguredError``.
/// - `headers` (string array, optional): each entry is a colon-separated `"Name: Value"` pair,
///   collected into a ``HeaderGroup``. Entries sharing the same name (case-sensitively) collapse
///   to one, the later entry winning, so a repeated header name (e.g. two `Accept` values) isn't
///   preserved; declare it directly with ``HeaderGroup/init(content:)`` instead if that matters.
/// - `queries` (string array, optional): each entry is an equals-separated `"name=value"` pair,
///   collected into a ``QueryGroup``. Every entry is kept, in order, so a repeated name
///   (`["tag=a", "tag=b"]`) is sent as `?tag=a&tag=b`.
/// - `authorization` (scoped, optional): passed to ``Authorization``. Reads `authorization.scheme`
///   (`"basic"` or `"bearer"`); `"basic"` additionally reads `authorization.username` and
///   `authorization.password` (or, absent those, a pre-encoded `authorization.credentials`), while
///   `"bearer"` reads `authorization.token`.
/// - `dnsOverrides` (string array, optional): each entry is a colon-separated `"host:IP"` pair,
///   one ``DNSOverride`` per entry.
/// - `urlOverrides` (string array, optional): each entry is a `"origin|destination"` pair (both
///   full `"scheme://host[/path]"` strings, so `:`/`/` couldn't serve as the separator the way
///   they do for `dnsOverrides`/`headers`), collected into a single ``URLOverride``.
/// - `systemProxy` (bool, optional, default: `false`): includes ``SystemProxy`` when `true`.
/// - `proxy` (scoped, optional): passed to ``Proxy``. Reads `proxy.enabled` (default `false`;
///   skipped entirely when not `true`), `proxy.host` (required), `proxy.port` (required for
///   `"http"`, defaults to `1080` for `"socks"`), and `proxy.type` (`"http"` or `"socks"`, default
///   `"http"`). Also reads `proxy.authorization` (same shape as the top-level `authorization`
///   key; for a `"socks"` proxy only `scheme: "basic"` with `username` and `password`, which are
///   the SOCKS5 user name and password sent in clear text, with the sizes ``Proxy`` documents)
///   and, for `"http"` proxies only, `proxy.connectHeaders` (string array, colon-separated
///   pairs, sent only on the proxy's `CONNECT` request).
/// - `cachePolicy` (string, optional): `"memory"`, `"disk"`, or `"all"`, passed to
///   ``Property/cachePolicy(_:)``.
/// - `cacheStrategy` (string, optional): `"ignoreCachedData"`, `"reloadAndValidateCachedData"`,
///   `"returnCachedDataElseLoad"`, or `"useCachedDataOnly"` (the ``CacheStrategy`` case names
///   verbatim), passed to ``Property/cacheStrategy(_:)``.
/// - `secureConnection` (scoped, optional): reads `secureConnection.trustRoots`,
///   `secureConnection.additionalTrustRoots`, and `secureConnection.certificates` (each a string
///   path to a `PEM` file, passed to ``TrustRoots``, ``AdditionalTrustRoots``, and ``Certificates``
///   respectively; none of these require nesting inside a `SecureConnection`, so each is included
///   independently); `secureConnection.privateKey` (scoped: `.file` required, `.format`
///   (`"pem"`/`"der"`, default `"pem"`), `.password` optional, treated as secret) passed to
///   ``PrivateKey``; `secureConnection.tlsMinimumVersion`/`secureConnection.tlsMaximumVersion`
///   (`"1.0"`/`"1.1"`/`"1.2"`/`"1.3"`), passed to ``SecureConnection/version(minimum:)``/
///   ``SecureConnection/version(maximum:)`` (these two, unlike the rest, do require a
///   `SecureConnection` wrapper, since they configure `SecureConnection` itself rather than a
///   certificate); and `secureConnection.spkiPinning` (scoped, optional, present only when
///   `secureConnection.spkiPinning.pins` is set), passed to ``SPKIPinning``/``SPKIHash``. Reads
///   `secureConnection.spkiPinning.pins` (string array, required, non-empty, each entry a
///   Base64-encoded SHA-256 SPKI digest) and `secureConnection.spkiPinning.policy` (`"strict"` or
///   `"audit"`, default `"strict"`). Only SHA-256 pins are supported through `Configured`; use
///   ``SPKIHash/init(_:algorithm:)-(S,_)`` directly for SHA-384/SHA-512 pins.
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
///   is present, chained onto the same ``Session`` value: same as declaring
///   `Session().maximumConnectionsPerHost(x).maximumConcurrentConnections(y)` directly.
///
/// Every key is read independently and is optional: a missing key simply contributes nothing, the
/// same as any other absent property. A key that is present with a value of the wrong type (`pins`
/// written as one string, `tlsMinimumVersion` as a number, `proxy.enabled` as `"true"`, `timeout`
/// as `"30"`) is an error, never a missing key: reading it as one would turn off pinning, the
/// minimum TLS version or the proxy without a word. This holds for every key, and so does the
/// entry check of the pair lists (`headers`, `queries`, `dnsOverrides`, `urlOverrides`,
/// `proxy.connectHeaders`): an entry with no separator or with an empty name is an error, not
/// dropped, and a blank entry (what an empty environment variable, or one ending in a comma, reads
/// as) is skipped. A key defined with an empty value (`TIMEOUT=`) is not a missing key either: it
/// does not convert to a number, and is an error.
///
/// Each key is read with the provider's `fetch` accessors, which is what tells a missing key from
/// one of the wrong type. A provider that does I/O on `fetch` (a remote one, or a reloading file)
/// is asked once per key on every resolve. An explicit property declared after `Configured` in the same
/// `@PropertyBuilder` block still wins, following the same "last one wins" precedent already
/// established by ``BaseURL`` and ``DNSOverride``.
///
/// ## Secrets
///
/// Values that carry credentials are read as secret, so a `ConfigReader` with an access
/// reporter or logger redacts them instead of writing them out: `headers`, `queries`,
/// `authorization.username`, `authorization.password`, `authorization.credentials`,
/// `authorization.token`, the same four under `proxy.authorization`, `proxy.connectHeaders`, and
/// the private key password in the certificate settings. The user name is among them because some
/// services take an API key as the user name of a Basic credential. The two lists are marked as a whole because an entry can be an
/// `Authorization` header or an API key in a query, and which one is not known until it is read.
/// `baseURL` is not: it is read as a plain value, so a reporter writes it out, and a user name or
/// a password in it is an error. The error comes after the read, so the reporter has already
/// seen that value: keep credentials out of it from the start.
///
/// - Throws: ``ConfiguredError`` if any key holds a value of the wrong type, if an entry of a pair
///   list has no separator or an empty name, if `authorization.scheme` or `proxy.authorization.scheme` is
///   specified but invalid, if the fields the specified scheme requires are missing, if
///   `proxy.enabled` is `true`
///   but `proxy.host` is missing or `proxy.type` is unknown, if `proxy.port` is missing for an
///   `"http"` proxy, if `proxy.connectHeaders`, or a `proxy.authorization` that is not
///   `scheme: "basic"` with `username` and `password`, is specified for a `"socks"` proxy, if `cachePolicy`/`cacheStrategy` is specified but is none of the recognized values, if
///   `secureConnection.privateKey.format` is specified but is neither `"pem"` nor `"der"`, if
///   `secureConnection.tlsMinimumVersion`/`secureConnection.tlsMaximumVersion` is specified but is
///   none of the recognized values, if `secureConnection.spkiPinning.pins` is specified but empty
///   or `secureConnection.spkiPinning.policy` is specified but is neither `"strict"` nor `"audit"`,
///   if `redirect.mode` is specified but is neither `"follow"` nor `"disallow"`, or if `timeout` is
///   specified but negative, or if `baseURL` has a user name or a password in its authority.
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
            if let baseURL = try await Self.string(reader, "baseURL", context: .invalidBaseURLConfiguration) {
                try Self.baseURL(baseURL)
            }

            if let method = try await Self.string(reader, "method") {
                RequestMethod(HTTPMethod(method.uppercased()))
            }

            if let timeout = try await Self.int(reader, "timeout", context: .invalidTimeoutConfiguration) {
                try Self.timeout(seconds: timeout)
            }

            if let headerPairs = try await Self.stringArray(reader, "headers", isSecret: true) {
                HeaderGroup(Self.dictionary(try Self.pairs(headerPairs, separatedBy: ":")))
            }

            if let queryPairs = try await Self.stringArray(reader, "queries", isSecret: true) {
                let queries = try Self.pairs(queryPairs, separatedBy: "=")

                QueryGroup {
                    PropertyForEach(queries) {
                        Query(name: $0.key, value: $0.value)
                    }
                }
            }

            if let authorization = try await Self.authorization(reader.scoped(to: "authorization")) {
                authorization
            }

            if let dnsOverridePairs = try await Self.stringArray(reader, "dnsOverrides") {
                PropertyForEach(Self.dictionary(try Self.pairs(dnsOverridePairs, separatedBy: ":")), id: \.key) {
                    DNSOverride($0.value, from: $0.key)
                }
            }

            if let urlOverridePairs = try await Self.stringArray(reader, "urlOverrides") {
                URLOverride(Self.dictionary(try Self.pairs(urlOverridePairs, separatedBy: "|")))
            }

            if try await Self.bool(reader, "systemProxy") ?? false {
                SystemProxy()
            }

            try await Self.proxy(reader.scoped(to: "proxy"))

            if let cachePolicy = try await Self.string(reader, "cachePolicy", context: .invalidCachePolicy) {
                EmptyProperty().cachePolicy(try Self.cachePolicy(cachePolicy))
            }

            if let cacheStrategy = try await Self.string(reader, "cacheStrategy", context: .invalidCacheStrategy) {
                EmptyProperty().cacheStrategy(try Self.cacheStrategy(cacheStrategy))
            }

            let secureConnectionReader = reader.scoped(to: "secureConnection")

            if let trustRootsFile = try await Self.string(
                secureConnectionReader,
                "trustRoots",
                context: .invalidSecureConnectionConfiguration
            ) {
                TrustRoots(trustRootsFile)
            }

            if let additionalTrustRootsFile = try await Self.string(
                secureConnectionReader,
                "additionalTrustRoots",
                context: .invalidSecureConnectionConfiguration
            ) {
                AdditionalTrustRoots(additionalTrustRootsFile)
            }

            if let certificatesFile = try await Self.string(
                secureConnectionReader,
                "certificates",
                context: .invalidSecureConnectionConfiguration
            ) {
                Certificates(certificatesFile)
            }

            if let spkiPinning = try await Self.spkiPinning(secureConnectionReader.scoped(to: "spkiPinning")) {
                spkiPinning
            }

            if let privateKey = try await Self.privateKey(secureConnectionReader.scoped(to: "privateKey")) {
                privateKey
            }

            if let secureConnection = try await Self.secureConnectionVersion(secureConnectionReader) {
                secureConnection
            }

            if let redirect = try await Self.redirect(reader.scoped(to: "redirect")) {
                redirect
            }

            if let connectionLimits = try await Self.connectionLimits(reader) {
                connectionLimits
            }
        }
    }

    // MARK: - Private static methods

    // MARK: Typed reads
    //
    // The non-throwing `ConfigReader` getters (`string(forKey:)`, `bool(forKey:default:)`, ...)
    // return `nil` (or the default) for a key that is present with a value of the wrong type, so a
    // `tlsMinimumVersion: 1.3` written as a number, or `pins` written as one string, was read as
    // "not configured" and the request went out without the protection the file asked for. The
    // `fetch` getters throw on a value that cannot be converted and return `nil` only when the key
    // is absent. Every error is reported as a `ConfiguredError`, and none of the errors carries the
    // value, which can be a secret.

    private static func string(
        _ reader: ConfigReader,
        _ key: ConfigKey,
        isSecret: Bool = false,
        context: ConfiguredError.Context = .invalidConfigurationValue
    ) async throws -> String? {
        do {
            return try await reader.fetchString(forKey: key, isSecret: isSecret)
        } catch {
            throw ConfiguredError(context: context)
        }
    }

    private static func stringArray(
        _ reader: ConfigReader,
        _ key: ConfigKey,
        isSecret: Bool = false,
        context: ConfiguredError.Context = .invalidConfigurationValue
    ) async throws -> [String]? {
        do {
            return try await reader.fetchStringArray(forKey: key, isSecret: isSecret)
        } catch {
            throw ConfiguredError(context: context)
        }
    }

    private static func int(
        _ reader: ConfigReader,
        _ key: ConfigKey,
        context: ConfiguredError.Context = .invalidConfigurationValue
    ) async throws -> Int? {
        do {
            return try await reader.fetchInt(forKey: key)
        } catch {
            throw ConfiguredError(context: context)
        }
    }

    private static func bool(
        _ reader: ConfigReader,
        _ key: ConfigKey,
        context: ConfiguredError.Context = .invalidConfigurationValue
    ) async throws -> Bool? {
        do {
            return try await reader.fetchBool(forKey: key)
        } catch {
            throw ConfiguredError(context: context)
        }
    }

    // MARK: Builders

    private static func connectionLimits(_ reader: ConfigReader) async throws -> Session? {
        let maximumConnectionsPerHost = try await Self.int(reader, "maximumConnectionsPerHost")
        let maximumConcurrentConnections = try await Self.int(reader, "maximumConcurrentConnections")

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

    private static func baseURL(_ value: String) throws -> FlexibleURL {
        guard !URLUserInfo.isPresent(in: value) else {
            throw ConfiguredError(context: .invalidBaseURLConfiguration)
        }

        return FlexibleURL(value)
    }

    private static func timeout(seconds: Int) throws -> Timeout {
        guard seconds >= 0 else {
            throw ConfiguredError(context: .invalidTimeoutConfiguration)
        }

        return Timeout(.seconds(Int64(seconds)))
    }

    private static func redirect(_ reader: ConfigReader) async throws -> Session? {
        guard let mode = try await Self.string(reader, "mode", context: .invalidRedirectConfiguration) else {
            return nil
        }

        switch mode {
        case "follow":
            return Session().enableRedirectFollow(
                max: try await Self.int(reader, "maxRedirects", context: .invalidRedirectConfiguration) ?? 5,
                allowCycles: try await Self.bool(reader, "allowCycles", context: .invalidRedirectConfiguration)
                    ?? false
            )
        case "disallow":
            return Session().disableRedirect()
        default:
            throw ConfiguredError(context: .invalidRedirectConfiguration)
        }
    }

    private static func spkiPinning(
        _ reader: ConfigReader
    ) async throws -> SPKIPinning<PropertyForEach<[String], String, SPKIHash<SHA256>>>? {
        guard
            let pins = try await Self.stringArray(
                reader,
                "pins",
                context: .invalidSecureConnectionConfiguration
            )
        else {
            return nil
        }

        guard !pins.isEmpty else {
            throw ConfiguredError(context: .invalidSecureConnectionConfiguration)
        }

        let policy = try Self.spkiPinningPolicy(
            try await Self.string(reader, "policy", context: .invalidSecureConnectionConfiguration) ?? "strict"
        )

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

    private static func privateKey(_ reader: ConfigReader) async throws -> PrivateKey? {
        guard let file = try await Self.string(reader, "file", context: .invalidSecureConnectionConfiguration) else {
            return nil
        }

        let format = try Self.certificateFormat(
            try await Self.string(reader, "format", context: .invalidSecureConnectionConfiguration) ?? "pem"
        )

        if let password = try await Self.string(
            reader,
            "password",
            isSecret: true,
            context: .invalidSecureConnectionConfiguration
        ) {
            return PrivateKey(file, format: format, password: SecureBytes(password.utf8))
        }

        return PrivateKey(file, format: format)
    }

    private static func secureConnectionVersion(
        _ reader: ConfigReader
    ) async throws -> SecureConnection<EmptyProperty>? {
        let minimum = try await Self.string(
            reader,
            "tlsMinimumVersion",
            context: .invalidSecureConnectionConfiguration
        )
        .map(Self.tlsVersion)

        let maximum = try await Self.string(
            reader,
            "tlsMaximumVersion",
            context: .invalidSecureConnectionConfiguration
        )
        .map(Self.tlsVersion)

        guard minimum != nil || maximum != nil else {
            return nil
        }

        var secureConnection = SecureConnection()

        if let minimum {
            secureConnection = secureConnection.version(minimum: minimum)
        }

        if let maximum {
            #if canImport(NIOCore)
            secureConnection = secureConnection.version(maximum: maximum)
            #else
            // No portable equivalent: neither URLSessionConfiguration nor App Transport
            // Security exposes a maximum-TLS-version key. See `SecureConnection
            // .version(maximum:)`'s own doc comment. A config that asks for one in a build
            // without NIO fails loudly here rather than silently ignoring it.
            throw ConfiguredError(context: .invalidSecureConnectionConfiguration)
            #endif
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
    private static func proxy(_ reader: ConfigReader) async throws -> AnyProperty {
        guard try await Self.bool(reader, "enabled", context: .invalidProxyConfiguration) ?? false else {
            return AnyProperty(EmptyProperty())
        }

        guard let host = try await Self.string(reader, "host", context: .invalidProxyConfiguration) else {
            throw ConfiguredError(context: .invalidProxyConfiguration)
        }

        let credentials = try await Self.credentials(reader.scoped(to: "authorization"))
        let connectHeaderPairs = try await Self.stringArray(
            reader,
            "connectHeaders",
            isSecret: true,
            context: .invalidProxyConfiguration
        )

        switch try await Self.string(reader, "type", context: .invalidProxyConfiguration) ?? "http" {
        case "http":
            guard let port = try await Self.int(reader, "port", context: .invalidProxyConfiguration) else {
                throw ConfiguredError(context: .invalidProxyConfiguration)
            }

            let authorization = credentials.map(Self.proxyAuthorization)

            let connectHeaders =
                try connectHeaderPairs.map {
                    Self.dictionary(try Self.pairs($0, separatedBy: ":", context: .invalidProxyConfiguration))
                } ?? [:]

            return AnyProperty(
                Proxy(host: host, port: port, authorization: authorization) { () -> ProxyConnectHeaders in
                    // Built from `PropertyForEach`/`CustomHeader` rather than `HeaderGroup`:
                    // `Proxy` discovers its `connectHeaders` content by searching for raw
                    // `HeaderNode` leaves, but `HeaderGroup` wraps its headers into its own
                    // opaque leaf node first, so nesting it here would silently resolve to no
                    // headers at all.
                    PropertyForEach(connectHeaders, id: \.key) {
                        CustomHeader(name: $0.key, value: $0.value)
                    }
                }
            )
        case "socks":
            // SOCKS5 has no `CONNECT` request to carry headers, and takes a user name and a
            // password (RFC 1929) rather than an HTTP header: `scheme: "basic"` with
            // `username`/`password` is that, and `credentials` (an encoded header value) and
            // `bearer` are not.
            guard connectHeaderPairs == nil else {
                throw ConfiguredError(context: .invalidProxyConfiguration)
            }

            let port = try await Self.int(reader, "port", context: .invalidProxyConfiguration) ?? 1080

            guard let credentials else {
                return AnyProperty(Proxy(host: host, port: port, connection: .socks))
            }

            guard case .basic = credentials else {
                throw ConfiguredError(context: .invalidProxyConfiguration)
            }

            return AnyProperty(
                Proxy(
                    host: host,
                    port: port,
                    connection: .socks,
                    authorization: Self.proxyAuthorization(credentials)
                )
            )
        default:
            throw ConfiguredError(context: .invalidProxyConfiguration)
        }
    }

    private typealias ProxyConnectHeaders = PropertyForEach<[String: String], String, CustomHeader>

    private static func proxyAuthorization(_ credentials: Credentials) -> ProxyAuthorization {
        switch credentials {
        case .basic(let username, let password):
            return .basic(username: username, password: password)
        case .encodedBasic(let credentials):
            return .basic(credentials: credentials)
        case .bearer(let token):
            return .bearer(tokens: token)
        }
    }

    private static func authorization(_ reader: ConfigReader) async throws -> Authorization? {
        guard let credentials = try await Self.credentials(reader) else {
            return nil
        }

        switch credentials {
        case .basic(let username, let password):
            return Authorization(username: username, password: password)
        case .encodedBasic(let credentials):
            return Authorization(.basic, token: credentials)
        case .bearer(let token):
            return Authorization(.bearer, token: token)
        }
    }

    private enum Credentials {
        case basic(username: String, password: String)
        case encodedBasic(String)
        case bearer(String)
    }

    /// Reads `scheme` and the fields the scheme needs. A missing or mistyped field is reported as
    /// `invalidAuthorizationConfiguration`, for the proxy's authorization too.
    private static func credentials(_ reader: ConfigReader) async throws -> Credentials? {
        let invalid = ConfiguredError.Context.invalidAuthorizationConfiguration

        guard let scheme = try await Self.string(reader, "scheme", context: invalid) else {
            return nil
        }

        switch scheme {
        case "basic":
            if let username = try await Self.string(reader, "username", isSecret: true, context: invalid),
                let password = try await Self.string(reader, "password", isSecret: true, context: invalid)
            {
                return .basic(username: username, password: password)
            } else if let credentials = try await Self.string(
                reader,
                "credentials",
                isSecret: true,
                context: invalid
            ) {
                return .encodedBasic(credentials)
            } else {
                throw ConfiguredError(context: invalid)
            }
        case "bearer":
            guard let token = try await Self.string(reader, "token", isSecret: true, context: invalid) else {
                throw ConfiguredError(context: invalid)
            }
            return .bearer(token)
        default:
            throw ConfiguredError(context: invalid)
        }
    }

    private struct Pair: Sendable, Identifiable {
        let id: Int
        let key: String
        let value: String
    }

    /// Splits each entry on its first `separator`. An entry with no separator, or with an empty
    /// name, is an error: it used to be dropped without a word, so a typo in a header or a query
    /// disappeared from the request. Repeated names are kept, in order. A flag with no value
    /// (`?uploads`) has no way through `Query`, so it is an error here too: write it in `baseURL`.
    ///
    /// A blank entry is skipped: an environment variable defined and left empty (`HEADERS=`) or
    /// with a trailing comma (`QUERIES=a=1,`) is read by the provider as a list with an empty
    /// element, and it says nothing.
    private static func pairs(
        _ entries: [String],
        separatedBy separator: Character,
        context: ConfiguredError.Context = .invalidConfigurationValue
    ) throws -> [Pair] {
        try entries.enumerated().compactMap { index, entry in
            guard !entry.trimmingASCIIWhitespace().isEmpty else {
                return nil
            }

            guard let (key, value) = entry.splitOnFirst(separator), !key.isEmpty else {
                throw ConfiguredError(context: context)
            }

            return Pair(id: index, key: key, value: value)
        }
    }

    /// For the properties that have one value per name (headers, DNS and URL overrides): the later
    /// entry wins, same as when the property is declared directly.
    private static func dictionary(_ pairs: [Pair]) -> [String: String] {
        pairs.reduce(into: [:]) { $0[$1.key] = $1.value }
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
