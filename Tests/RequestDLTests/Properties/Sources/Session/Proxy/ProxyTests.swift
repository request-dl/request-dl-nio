//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct ProxyTests {

    @Test
    func proxy_whenHTTPConnectionWithoutAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                connection: .http
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
    }

    @Test
    func proxy_whenHTTPConnectionWithAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let credentials = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                authorization: .basic(credentials: credentials)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.authorization == .basicRawCredentials(credentials))
    }

    @Test
    func proxy_whenHTTPConnectionWithUsernamePasswordAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let username = UUID().uuidString
        let password = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                authorization: .basic(username: username, password: password)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(
            resolved.session.configuration.proxy?.authorization
                == .basic(username: username, password: password)
        )
    }

    @Test
    func proxy_whenHTTPConnectionWithBearerAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let tokens = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                authorization: .bearer(tokens: tokens)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.authorization == .bearer(tokens: tokens))
    }

    @Test
    func proxy_whenHTTPConnectionWithConnectHeaders() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let name = UUID().uuidString
        let value = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port) {
                CustomHeader(name: name, value: value)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: name) == value)
    }

    @Test
    func proxy_whenHTTPConnectionWithConnectHeadersFromHeaderGroup() async throws {
        // Given
        // `HeaderGroup` must not wrap its resolved headers into an opaque leaf node, which
        // would be invisible to `Proxy`'s `search(for: HeaderNode.self)` over its
        // `connectHeaders` content, silently dropping every header composed through it here.
        let host = UUID().uuidString
        let port = 1_090
        let name = UUID().uuidString
        let value = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port) {
                HeaderGroup {
                    CustomHeader(name: name, value: value)
                }
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: name) == value)
    }

    @Test
    func proxy_whenHTTPConnectionWithAuthorizationAndConnectHeaders() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let credentials = UUID().uuidString
        let name = UUID().uuidString
        let value = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port, authorization: .basic(credentials: credentials)) {
                CustomHeader(name: name, value: value)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.authorization == .basicRawCredentials(credentials))
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: name) == value)
    }

    @Test
    func proxy_whenSOCKSConnectionWithoutAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                connection: .socks
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
    }

    @Test
    func proxy_whenSOCKSConnectionWithBasicAuthorization_convertsToSOCKSCredentials() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                connection: .socks,
                authorization: .basic(username: "user", password: "pass")
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.connectionProtocol == .socks)
        #expect(resolved.session.configuration.proxy?.authorization == .socks(username: "user", password: "pass"))
    }

    @Test
    func proxy_whenHTTPConnectionThroughTheConnectionInitializer_keepsTheHTTPShape() async throws {
        // When
        let resolved = try await resolve(
            Proxy(host: "proxy.example", port: 8_080, connection: .http, authorization: .bearer(tokens: "abc"))
        )

        // Then
        #expect(resolved.session.configuration.proxy?.connectionProtocol == .http)
        #expect(resolved.session.configuration.proxy?.authorization == .bearer(tokens: "abc"))
    }

    @Test
    func proxy_whenSOCKSConnectionWithEmptyPassword_isAllowed() async throws {
        // When
        let resolved = try await resolve(
            Proxy(
                host: "proxy.example",
                port: 1_080,
                connection: .socks,
                authorization: .basic(username: "u", password: "")
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.authorization == .socks(username: "u", password: ""))
    }

    @Test
    func proxy_whenSOCKSCredentialsAtTheLimits_areAllowed() async throws {
        // Given
        let username = String(repeating: "a", count: 255)
        let password = String(repeating: "é", count: 127) + "a"  // 255 bytes in UTF-8

        // When
        let resolved = try await resolve(
            Proxy(
                host: "proxy.example",
                port: 1_080,
                connection: .socks,
                authorization: .basic(username: username, password: password)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.authorization == .socks(username: username, password: password))
    }

    @Test(arguments: [
        (ProxyAuthorizationError.Reason.socksRequiresUsernameAndPassword, "user name and a password"),
        (.socksUsernameLength(actual: 0), "user name has 0 bytes"),
        (.socksPasswordLength(actual: 300), "password has 300 bytes"),
        (.socksCredentialsContainNUL, "NUL character"),
    ])
    func proxyAuthorizationError_descriptionSaysWhatIsWrong(
        _ reason: ProxyAuthorizationError.Reason,
        _ fragment: String
    ) throws {
        // Given
        let mismatch: Internals.Proxy.Authorization.Mismatch

        switch reason {
        case .socksRequiresUsernameAndPassword: mismatch = .httpShapeOnSOCKSProxy
        case .socksUsernameLength(let actual): mismatch = .socksUsernameLength(actual)
        case .socksPasswordLength(let actual): mismatch = .socksPasswordLength(actual)
        case .socksCredentialsContainNUL: mismatch = .socksCredentialContainsNUL
        case .socksAuthenticationRejected: preconditionFailure("Not a mismatch: see the rejection test below.")
        }

        // When
        let error = ProxyAuthorizationError(mismatch)

        // Then
        #expect(error.reason == reason)
        #expect(error.description.contains(fragment))
        #expect(error.description.hasSuffix("The request was not sent."))
    }

    @Test
    func proxy_whenSOCKSBearerAuthorization_throwsWithoutTheSecret() async throws {
        // Given
        let token = "super-secret-token"

        // When
        let error = await #expect(throws: ProxyAuthorizationError.self) {
            try await resolve(
                Proxy(host: "proxy.example", port: 1_080, connection: .socks, authorization: .bearer(tokens: token))
            )
        }

        // Then
        #expect(error?.reason == .socksRequiresUsernameAndPassword)
        #expect(!String(describing: error).contains(token))
    }

    @Test
    func proxy_whenSOCKSRawBasicCredentials_throws() async throws {
        // Then
        let error = await #expect(throws: ProxyAuthorizationError.self) {
            // When
            try await resolve(
                Proxy(
                    host: "proxy.example",
                    port: 1_080,
                    connection: .socks,
                    authorization: .basic(credentials: "dXNlcjpwYXNz")
                )
            )
        }

        #expect(error?.reason == .socksRequiresUsernameAndPassword)
    }

    @Test
    func proxy_whenSOCKSUsernameIsEmpty_throws() async throws {
        let error = await #expect(throws: ProxyAuthorizationError.self) {
            try await resolve(
                Proxy(
                    host: "proxy.example",
                    port: 1_080,
                    connection: .socks,
                    authorization: .basic(username: "", password: "p")
                )
            )
        }

        #expect(error?.reason == .socksUsernameLength(actual: 0))
    }

    @Test
    func proxy_whenSOCKSUsernameHas256Bytes_throws() async throws {
        let username = String(repeating: "a", count: 256)

        let error = await #expect(throws: ProxyAuthorizationError.self) {
            try await resolve(
                Proxy(
                    host: "proxy.example",
                    port: 1_080,
                    connection: .socks,
                    authorization: .basic(username: username, password: "p")
                )
            )
        }

        #expect(error?.reason == .socksUsernameLength(actual: 256))
        #expect(!String(describing: error).contains(username))
    }

    @Test
    func proxy_whenSOCKSPasswordHas256Bytes_throws() async throws {
        // 128 two-byte characters: the limit is on bytes, not on characters.
        let password = String(repeating: "é", count: 128)

        let error = await #expect(throws: ProxyAuthorizationError.self) {
            try await resolve(
                Proxy(
                    host: "proxy.example",
                    port: 1_080,
                    connection: .socks,
                    authorization: .basic(username: "u", password: password)
                )
            )
        }

        #expect(error?.reason == .socksPasswordLength(actual: 256))
    }

    @Test(arguments: [("us\u{0}er", "pass"), ("user", "pa\u{0}ss"), ("user", "\u{0}")])
    func proxy_whenSOCKSCredentialsHaveANUL_throws(_ username: String, _ password: String) async throws {
        let error = await #expect(throws: ProxyAuthorizationError.self) {
            try await resolve(
                Proxy(
                    host: "proxy.example",
                    port: 1_080,
                    connection: .socks,
                    authorization: .basic(username: username, password: password)
                )
            )
        }

        #expect(error?.reason == .socksCredentialsContainNUL)
        #expect(error.map { !$0.description.contains("\u{0}") } == true)
    }

    @Test
    func proxy_whenHTTPCredentialsHaveANUL_isNotTouched() async throws {
        // The restriction is SOCKS5's: an HTTP proxy's header is as it always was.
        let resolved = try await resolve(
            Proxy(
                host: "proxy.example",
                port: 8_080,
                connection: .http,
                authorization: .basic(username: "u\u{0}", password: "p")
            )
        )

        #expect(resolved.session.configuration.proxy?.authorization == .basic(username: "u\u{0}", password: "p"))
    }

    @Test(arguments: [
        ProxyAuthorizationError.Reason.socksRequiresUsernameAndPassword,
        .socksUsernameLength(actual: 0),
        .socksUsernameLength(actual: 256),
        .socksPasswordLength(actual: 256),
        .socksCredentialsContainNUL,
    ])
    func proxyAuthorizationError_describesItselfWithoutAnyCredentials(_ reason: ProxyAuthorizationError.Reason) {
        let error = ProxyAuthorizationError(
            {
                switch reason {
                case .socksRequiresUsernameAndPassword: return .httpShapeOnSOCKSProxy
                case .socksUsernameLength(let actual): return .socksUsernameLength(actual)
                case .socksPasswordLength(let actual): return .socksPasswordLength(actual)
                case .socksCredentialsContainNUL: return .socksCredentialContainsNUL
                case .socksAuthenticationRejected: preconditionFailure("Not a mismatch: see the rejection test above.")
                }
            }()
        )

        #expect(error.reason == reason)
        #expect(error.description.contains("SOCKS"))
        #expect(error.description.contains("not sent"))
    }

    @Test
    func proxyAuthorizationError_whenRejectedByTheProxy_keepsTheCauseAndNoCredentials() {
        // Given
        struct Cause: Error, CustomStringConvertible {
            let description = "status 1"
        }

        // When
        let error = ProxyAuthorizationError(Internals.SOCKSAuthenticationRejectedError(underlying: Cause()))

        // Then
        #expect(error.reason == .socksAuthenticationRejected)
        #expect(error.underlyingError is Cause)
        #expect(error.description.contains("rejected the user name and the password"))
        #expect(!error.description.contains("status 1"))
        #expect(error.debugDescription.hasSuffix("Underlying error: status 1"))
        // The cause is for diagnosis, not part of what the error is equal to.
        let other = ProxyAuthorizationError(Internals.SOCKSAuthenticationRejectedError(underlying: CancellationError()))
        #expect(error == other)
        #expect(error != ProxyAuthorizationError(.socksCredentialContainsNUL))
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Proxy(
            host: UUID().uuidString,
            port: 1_000,
            connection: .http
        )

        // Then
        try await assertNever(property.body)
    }
}
