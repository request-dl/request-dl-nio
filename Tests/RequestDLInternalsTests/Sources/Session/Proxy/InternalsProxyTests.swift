//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct InternalsProxyTests {

    /// `Internals.Session.Configuration.==` uses `Internals.Proxy.==` (transitively) as
    /// `Internals.ClientManager`'s pooled-client cache key. `connectHeaders` is where proxy-auth
    /// secrets distinct per session commonly live, so two proxies differing only there must
    /// compare unequal. Otherwise one session's pooled client (built with its own CONNECT headers
    /// baked in) could be silently handed to a request for a *different* session's proxy
    /// credentials, leaking one session's proxy authorization into another's traffic.
    @Test
    func proxy_whenConnectHeadersDiffer_shouldNotBeEqual() {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = Internals.HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "abc123")

        // When
        let lhs = Internals.Proxy(host: host, port: port, connection: .http, authorization: nil)
        let rhs = Internals.Proxy(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func proxy_whenConnectHeadersMatch_shouldBeEqualAndHashEqual() {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = Internals.HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "abc123")

        // When
        let lhs = Internals.Proxy(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )
        let rhs = Internals.Proxy(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        // Then
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    // MARK: - SOCKS5 credentials

    @Test
    func proxy_whenSOCKSCredentialsDiffer_shouldNotBeEqual() {
        // The pooled client is keyed on this: two sessions with different SOCKS credentials must
        // not share a client, whose proxy connection is authenticated as one of them.
        let base = Internals.Proxy(
            host: "p",
            port: 1,
            connection: .socks,
            authorization: .socks(username: "u", password: "a")
        )
        let otherPassword = Internals.Proxy(
            host: "p",
            port: 1,
            connection: .socks,
            authorization: .socks(username: "u", password: "b")
        )
        let otherUsername = Internals.Proxy(
            host: "p",
            port: 1,
            connection: .socks,
            authorization: .socks(username: "v", password: "a")
        )
        let none = Internals.Proxy(host: "p", port: 1, connection: .socks, authorization: nil)

        #expect(base != otherPassword)
        #expect(base != otherUsername)
        #expect(base != none)
    }

    @Test
    func proxy_whenSOCKSCredentialsMatch_shouldBeEqualAndHashEqual() {
        let lhs = Internals.Proxy(
            host: "p",
            port: 1,
            connection: .socks,
            authorization: .socks(username: "u", password: "")
        )
        let rhs = Internals.Proxy(
            host: "p",
            port: 1,
            connection: .socks,
            authorization: .socks(username: "u", password: "")
        )

        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test
    func authorization_whenSOCKSShapeAndHTTPShapeCarrySameStrings_shouldNotBeEqual() {
        #expect(
            Internals.Proxy.Authorization.socks(username: "u", password: "p")
                != .basic(username: "u", password: "p")
        )
    }

    @Test
    func authorization_description_doesNotContainTheSecrets() {
        let secrets = ["sekret-user", "sekret-pass", "sekret-raw", "sekret-token"]

        let authorizations: [Internals.Proxy.Authorization] = [
            .socks(username: "sekret-user", password: "sekret-pass"),
            .basic(username: "sekret-user", password: "sekret-pass"),
            .basicRawCredentials("sekret-raw"),
            .bearer(tokens: "sekret-token"),
        ]

        for authorization in authorizations {
            let proxy = Internals.Proxy(host: "p", port: 1, connection: .socks, authorization: authorization)

            var dumped = ""
            dump(proxy, to: &dumped)

            let outputs = [
                String(describing: authorization),
                String(reflecting: authorization),
                "\(authorization)",
                String(describing: proxy),
                String(reflecting: proxy),
                dumped,
                String(describing: Mirror(reflecting: authorization).children.map { "\($0)" }),
            ]

            for output in outputs {
                for secret in secrets {
                    #expect(!output.contains(secret), "\(output) leaks \(secret)")
                }
            }
        }
    }

    @Test
    func validate_whenSOCKSCredentialsAtTheLimits_succeeds() throws {
        try Internals.Proxy.Authorization.socks(username: "u", password: "").validate(for: .socks)
        try Internals.Proxy.Authorization.socks(
            username: String(repeating: "a", count: 255),
            password: String(repeating: "b", count: 255)
        ).validate(for: .socks)
    }

    @Test
    func validate_whenSOCKSCredentialsOutOfRange_throwsTheSize() {
        #expect(throws: Internals.Proxy.Authorization.Mismatch.socksUsernameLength(0)) {
            try Internals.Proxy.Authorization.socks(username: "", password: "p").validate(for: .socks)
        }

        #expect(throws: Internals.Proxy.Authorization.Mismatch.socksUsernameLength(256)) {
            try Internals.Proxy.Authorization.socks(username: String(repeating: "a", count: 256), password: "")
                .validate(for: .socks)
        }

        // Bytes, not characters: 128 two-byte characters.
        #expect(throws: Internals.Proxy.Authorization.Mismatch.socksPasswordLength(256)) {
            try Internals.Proxy.Authorization.socks(username: "u", password: String(repeating: "é", count: 128))
                .validate(for: .socks)
        }
    }

    @Test
    func validate_whenTheShapeDoesNotFitTheProtocol_throws() {
        for authorization in [
            Internals.Proxy.Authorization.basic(username: "u", password: "p"),
            .basicRawCredentials("dTpw"),
            .bearer(tokens: "t"),
        ] {
            #expect(throws: Internals.Proxy.Authorization.Mismatch.httpShapeOnSOCKSProxy) {
                try authorization.validate(for: .socks)
            }
            // and they are fine on HTTP
            #expect(throws: Never.self) { try authorization.validate(for: .http) }
        }

        #expect(throws: Internals.Proxy.Authorization.Mismatch.socksShapeOnHTTPProxy) {
            try Internals.Proxy.Authorization.socks(username: "u", password: "p").validate(for: .http)
        }
    }
}

// The remaining tests all read `configuration.build().httpClientConfiguration`, and both
// `Output` (the type `build()` returns) and `.httpClientConfiguration`'s
// `HTTPClient.Configuration` (AsyncHTTPClient) only exist under `canImport(NIOCore)`.
#if canImport(NIOCore)

extension InternalsProxyTests {

    @Test
    func proxy_whenHTTPConnectionWithoutAuthorization() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .http,
            authorization: nil
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.host == host)
        #expect(resolved.proxy?.port == port)
    }

    @Test
    func proxy_whenHTTPConnectionWithAuthorization() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090
        let credentials = UUID().uuidString

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .http,
            authorization: .basicRawCredentials(credentials)
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.host == host)
        #expect(resolved.proxy?.port == port)
        #expect(resolved.proxy?.authorization == .basic(credentials: credentials))
    }

    @Test
    func proxy_whenSOCKSConnectionWithoutAuthorization() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .socks,
            authorization: nil
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.host == host)
        #expect(resolved.proxy?.port == port)
    }

    @Test
    func proxy_whenHTTPConnectionWithConnectHeaders() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = Internals.HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "first")
        connectHeaders.add(name: "X-Proxy-Token", value: "second")

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.connectHeaders["X-Proxy-Token"] == ["first", "second"])
    }
    @Test
    func proxy_whenSOCKSConnectionWithCredentials_buildsTheAuthenticatedSOCKSProxy() throws {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.proxy = .init(
            host: "proxy.example",
            port: 1_081,
            connection: .socks,
            authorization: .socks(username: "user", password: "sekret")
        )

        // When
        let resolved = try #require(try configuration.build().httpClientConfiguration.proxy)

        // Then: the same proxy AsyncHTTPClient builds from the credentials itself...
        #expect(
            resolved == (try .socksServer(host: "proxy.example", port: 1_081, username: "user", password: "sekret"))
        )
        // ...which differs from the one without them.
        #expect(resolved != .socksServer(host: "proxy.example", port: 1_081))
        #expect(resolved.authorization == nil)
        // And is safe to log.
        #expect(String(describing: resolved).contains("user"))
        #expect(!String(describing: resolved).contains("sekret"))
    }

    @Test
    func proxy_whenSOCKSConnectionWithAnEmptyPassword_builds() throws {
        var configuration = Internals.Session.Configuration()
        configuration.proxy = .init(
            host: "proxy.example",
            port: 1_081,
            connection: .socks,
            authorization: .socks(username: "user", password: "")
        )

        let resolved = try #require(try configuration.build().httpClientConfiguration.proxy)

        #expect(resolved == (try .socksServer(host: "proxy.example", port: 1_081, username: "user", password: "")))
    }

    @Test(arguments: [
        Internals.Proxy.Authorization.basic(username: "u", password: "p"),
        .basicRawCredentials("dTpw"),
        .bearer(tokens: "t"),
    ])
    func proxy_whenSOCKSConnectionWithAnHTTPShape_throwsInsteadOfDroppingIt(
        _ authorization: Internals.Proxy.Authorization
    ) {
        var configuration = Internals.Session.Configuration()
        configuration.proxy = .init(host: "proxy.example", port: 1, connection: .socks, authorization: authorization)

        #expect(throws: Internals.Proxy.Authorization.Mismatch.httpShapeOnSOCKSProxy) {
            try configuration.build()
        }
    }

    @Test
    func proxy_whenSOCKSCredentialsAreTooLong_throwsBeforeBuildingAnything() {
        var configuration = Internals.Session.Configuration()
        configuration.proxy = .init(
            host: "proxy.example",
            port: 1,
            connection: .socks,
            authorization: .socks(username: "u", password: String(repeating: "p", count: 256))
        )

        #expect(throws: Internals.Proxy.Authorization.Mismatch.socksPasswordLength(256)) {
            try configuration.build()
        }
    }

    @Test
    func proxy_whenHTTPConnectionWithTheSOCKSShape_throws() {
        var configuration = Internals.Session.Configuration()
        configuration.proxy = .init(
            host: "proxy.example",
            port: 1,
            connection: .http,
            authorization: .socks(username: "u", password: "p")
        )

        #expect(throws: Internals.Proxy.Authorization.Mismatch.socksShapeOnHTTPProxy) {
            try configuration.build()
        }
    }
}

#endif
