//
// See LICENSE for this package's licensing information.
//

// `LocalSOCKSProxy` is NIO-only (see its own doc comment), and `Session.requiredExecutor(.nio)`
// does not exist without NIOCore.
#if canImport(NIOCore)

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.TimeInterval
import struct Foundation.UUID
#endif

#if canImport(Darwin)
import Foundation
#endif

/// SOCKS5 username/password authentication (RFC 1929) through the public `DataTask` and `Proxy`
/// API, against `LocalSOCKSProxy`, a real server that demands the credentials and records the
/// bytes it receives: what is asserted is what the proxy saw on the wire, not what the client was
/// asked to send.
///
/// The destination is `localhost`, which the proxy dials itself; `.nio` and
/// `.nioTransportServices` do not bypass a proxy for loopback the way `URLSession` does, so the
/// `.urlSession` half of this is in `InternalsURLSessionClientSOCKSAuthenticationTests`, with a
/// destination that is not loopback.
struct ProxySOCKSAuthenticationTests {

    // MARK: - Private types

    private struct Outcome {
        let result: Result<String, any Error>
        let elapsed: TimeInterval
    }

    // MARK: - Private methods

    /// Runs one `DataTask` through `proxy` and reports its outcome.
    private func run(
        through proxy: LocalSOCKSProxy,
        executor: Session.Executor = .nio,
        authorization: ProxyAuthorization?,
        destination: String? = nil
    ) async throws -> Outcome {
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello Through SOCKS"), at: uri)

        let session = Session.localServer.requiredExecutor(executor)
        // `Date`, not `ContinuousClock`: the package still builds for macOS 12 and iOS 15.
        let start = Date()

        do {
            let data = try await DataTask {
                BaseURL(destination ?? localServer.baseURL)
                Path(uri)

                session

                if let authorization {
                    Proxy(host: proxy.host, port: proxy.port, connection: .socks, authorization: authorization)
                } else {
                    Proxy(host: proxy.host, port: proxy.port, connection: .socks)
                }

                SecureConnection {
                    TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
                // A destination by another name than the certificate's cannot be verified.
                .verification(destination == nil ? .fullVerification : .none)
            }
            .extractPayload()
            .result()

            localServer.cleanup(at: uri)

            return Outcome(
                result: .success(try HTTPResult<String>(data).response),
                elapsed: Date().timeIntervalSince(start)
            )
        } catch {
            localServer.cleanup(at: uri)
            return Outcome(result: .failure(error), elapsed: Date().timeIntervalSince(start))
        }
    }

    /// Runs `body` against a proxy and shuts the proxy down afterwards, whether `body` threw or not.
    private func withProxy(
        credentials: LocalSOCKSProxy.Credentials? = nil,
        redirect: (host: String, port: Int)? = nil,
        _ body: (LocalSOCKSProxy) async throws -> Void
    ) async throws {
        let proxy = try await LocalSOCKSProxy.start(
            credentials: credentials,
            redirect: redirect.map { .init(host: $0.host, port: $0.port) }
        )

        do {
            try await body(proxy)
        } catch {
            try? await proxy.shutdown()
            throw error
        }

        try await proxy.shutdown()
    }

    private static var executors: [Session.Executor] {
        #if canImport(Darwin)
        return [.nio, .nioTransportServices]
        #else
        return [.nio]
        #endif
    }

    // MARK: - Success

    @Test(arguments: executors)
    func socks_whenCredentialsMatch_authenticatesAndCarriesTraffic(_ executor: Session.Executor) async throws {
        // Given
        try await withProxy(credentials: .init(username: "user", password: "pass")) { proxy in

            // When
            let outcome = try await run(
                through: proxy,
                executor: executor,
                authorization: .basic(username: "user", password: "pass")
            )

            // Then
            #expect(try outcome.result.get() == "Hello Through SOCKS")
            #expect(proxy.connectAttempts.count >= 1)
            // Offered username/password next to no authentication, then sent the exact bytes.
            #expect(proxy.observations.greetings.first?.contains(0x02) == true)
            #expect(
                proxy.observations.authenticationAttempts.first
                    == .init(username: Array("user".utf8), password: Array("pass".utf8), accepted: true)
            )
        }
    }

    @Test
    func socks_whenPasswordIsEmpty_authenticates() async throws {
        try await withProxy(credentials: .init(username: "user", password: "")) { proxy in

            let outcome = try await run(through: proxy, authorization: .basic(username: "user", password: ""))

            #expect(try outcome.result.get() == "Hello Through SOCKS")
            #expect(
                proxy.observations.authenticationAttempts == [
                    .init(username: Array("user".utf8), password: [], accepted: true)
                ]
            )
        }
    }

    @Test
    func socks_whenCredentialsAreNotASCII_sendsThemAsUTF8() async throws {
        let username = "usér😀"
        let password = "pässwörd:@%"
        try await withProxy(credentials: .init(username: username, password: password)) { proxy in

            let outcome = try await run(through: proxy, authorization: .basic(username: username, password: password))

            #expect(try outcome.result.get() == "Hello Through SOCKS")
            #expect(
                proxy.observations.authenticationAttempts
                    == [.init(username: Array(username.utf8), password: Array(password.utf8), accepted: true)]
            )
        }
    }

    @Test
    func socks_whenCredentialsAreExactly255Bytes_authenticates() async throws {
        let username = String(repeating: "u", count: 255)
        let password = String(repeating: "é", count: 127) + "p"
        #expect(password.utf8.count == 255)

        try await withProxy(credentials: .init(username: username, password: password)) { proxy in

            let outcome = try await run(through: proxy, authorization: .basic(username: username, password: password))

            #expect(try outcome.result.get() == "Hello Through SOCKS")
            #expect(proxy.observations.authenticationAttempts.first?.username.count == 255)
            #expect(proxy.observations.authenticationAttempts.first?.password.count == 255)
        }
    }

    @Test
    func socks_whenProxyDoesNotRequireAuthentication_credentialsAreNotSent() async throws {
        // Given: a proxy that takes no authentication, and credentials configured anyway.
        try await withProxy { proxy in

            // When
            let outcome = try await run(through: proxy, authorization: .basic(username: "user", password: "pass"))

            // Then: it works, and the credentials never left.
            #expect(try outcome.result.get() == "Hello Through SOCKS")
            #expect(proxy.observations.authenticationAttempts.isEmpty)
            #expect(proxy.observations.greetings.first?.contains(0x00) == true)
        }
    }

    // MARK: - Failure

    @Test(arguments: executors)
    func socks_whenPasswordIsWrong_failsPromptlyAndIsNotRetried(_ executor: Session.Executor) async throws {
        // Given
        try await withProxy(credentials: .init(username: "user", password: "pass")) { proxy in

            // When
            let outcome = try await run(
                through: proxy,
                executor: executor,
                authorization: .basic(username: "user", password: "WRONG")
            )

            // Then
            let error = try #require(
                { () -> (any Error)? in
                    if case .failure(let error) = outcome.result { return error }
                    return nil
                }()
            )

            #expect(outcome.elapsed < 5)
            // The proxy was asked once and rejected: nothing retried the same wrong credentials.
            //
            // Not a fixed sleep, which on a slow machine ends before a late retry would have come
            // and asserts nothing: a request with the right password goes through the same proxy
            // and has to finish first. Whatever the first one still had in flight reaches the
            // proxy ahead of it, so the proxy's record is complete when this returns, however long
            // that took.
            let barrier = try await run(
                through: proxy,
                executor: executor,
                authorization: .basic(username: "user", password: "pass")
            )
            #expect(try barrier.result.get() == "Hello Through SOCKS")
            #expect(proxy.observations.authenticationAttempts.map(\.accepted) == [false, true])
            #expect(proxy.connectAttempts.count == 1)
            // The same typed error on every executor, with what the executor reported kept as its
            // cause. It says what happened, and not what the password was.
            let typed = try #require(error as? ProxyAuthorizationError)
            #expect(typed.reason == .socksAuthenticationRejected)
            #expect(!String(describing: error).contains("WRONG"))
            #expect(!String(reflecting: error).contains("WRONG"))
            // The type comes from the fork of swift-nio-extras, which the test target does not
            // link, hence the name.
            let underlying = try #require(typed.underlyingError)
            #expect(String(reflecting: type(of: underlying)) == "NIOSOCKS.SOCKSError.AuthenticationFailed")
        }
    }

    @Test
    func socks_whenProxyRequiresCredentialsAndNoneAreConfigured_failsPromptly() async throws {
        try await withProxy(credentials: .init(username: "user", password: "pass")) { proxy in

            let outcome = try await run(through: proxy, authorization: nil)

            guard case .failure = outcome.result else {
                Issue.record("A proxy that needs credentials was used without any")
                return
            }

            #expect(outcome.elapsed < 5)
            #expect(proxy.observations.authenticationAttempts.isEmpty)
            #expect(proxy.connectAttempts.count == 0)
        }
    }

    @Test(arguments: [
        ProxyAuthorization.bearer(tokens: "token"),
        ProxyAuthorization.basic(credentials: "dXNlcjpwYXNz"),
    ])
    func socks_whenAuthorizationIsAnHTTPHeader_throwsBeforeConnecting(_ authorization: ProxyAuthorization) async throws
    {
        try await withProxy(credentials: .init(username: "user", password: "pass")) { proxy in

            let outcome = try await run(through: proxy, authorization: authorization)

            guard case .failure(let error) = outcome.result else {
                Issue.record("An HTTP authorization header was accepted by a SOCKS proxy")
                return
            }

            #expect((error as? ProxyAuthorizationError)?.reason == .socksRequiresUsernameAndPassword)
            #expect(proxy.observations.greetings.isEmpty)
        }
    }

    @Test(arguments: [
        ("", "pass", ProxyAuthorizationError.Reason.socksUsernameLength(actual: 0)),
        (String(repeating: "u", count: 256), "pass", .socksUsernameLength(actual: 256)),
        ("user", String(repeating: "p", count: 256), .socksPasswordLength(actual: 256)),
    ])
    func socks_whenCredentialsAreOutOfRange_throwsBeforeConnecting(
        _ username: String,
        _ password: String,
        _ expected: ProxyAuthorizationError.Reason
    ) async throws {
        try await withProxy(credentials: .init(username: "user", password: "pass")) { proxy in

            let outcome = try await run(through: proxy, authorization: .basic(username: username, password: password))

            guard case .failure(let error) = outcome.result else {
                Issue.record("Out of range credentials were accepted")
                return
            }

            #expect((error as? ProxyAuthorizationError)?.reason == expected)
            #expect(proxy.observations.greetings.isEmpty)
        }
    }

    @Test
    func socks_whenCredentialsHaveANUL_throwsBeforeConnecting() async throws {
        // CFNetwork would cut them at the NUL, so `.urlSession` would send other credentials than `.nio`.
        for (username, password, expected) in [
            ("us\u{0}er", "pass", ProxyAuthorizationError.Reason.socksCredentialsContainNUL),
            ("user", "pa\u{0}ss", .socksCredentialsContainNUL),
            ("user", "\u{0}", .socksCredentialsContainNUL),
        ] {
            try await withProxy(credentials: .init(username: "user", password: "pass")) { proxy in
                let outcome = try await run(
                    through: proxy,
                    authorization: .basic(username: username, password: password)
                )

                guard case .failure(let error) = outcome.result else {
                    Issue.record("Credentials with a NUL were accepted")
                    return
                }

                #expect((error as? ProxyAuthorizationError)?.reason == expected)
                #expect(proxy.observations.greetings.isEmpty)
            }
        }
    }

    // MARK: - Executor selection

    #if canImport(Darwin)

    /// 255 bytes is valid SOCKS5, but CFNetwork sends 254 of them
    /// (`InternalsURLSessionClientSOCKSAuthenticationTests`), so `.urlSession` is not an option for
    /// it: pinning it throws, and the default resolution picks another executor instead of one that
    /// cannot authenticate.
    @Test
    func socks_whenCredentialsAre255Bytes_urlSessionCannotBeRequired() async throws {
        // Given
        let username = String(repeating: "u", count: 255)

        let task = DataTask {
            BaseURL("localhost")

            Session()
                .requiredExecutor(.urlSession)

            Proxy(
                host: "127.0.0.1",
                port: 1,
                connection: .socks,
                authorization: .basic(username: username, password: "p")
            )
        }
        .extractPayload()

        // When
        let error = await #expect(throws: ExecutorRequirementError.self) {
            try await task.result()
        }

        // Then
        #expect(error?.requiredExecutor == .urlSession)
        #expect(error?.reasons == [.proxySOCKSCredentialsTooLongUnderURLSession])
        #expect(error?.description.contains("254 bytes") == true)
        #expect(!(error?.description.contains(username) ?? false))
    }

    @Test
    func socks_whenCredentialsAre255Bytes_automaticSelectionAvoidsURLSession() async throws {
        let username = String(repeating: "u", count: 255)

        let resolved = try await resolve(
            Proxy(
                host: "127.0.0.1",
                port: 1,
                connection: .socks,
                authorization: .basic(username: username, password: "p")
            )
        )

        #expect(resolved.session.configuration.resolveExecutor() != .urlSession)
    }

    /// The same proxy and credentials as the NIO tests above, through the public API on
    /// `.urlSession`. The destination is not loopback (macOS does not proxy loopback), so the
    /// proxy redirects what it is asked for to the local server.
    @Test
    func socks_onURLSession_authenticatesAndCarriesTraffic() async throws {
        let localServer = try await LocalServer(.standard)

        try await withProxy(credentials: .init(username: "user", password: "pass"), redirect: localServer.address) {
            proxy in
            let outcome = try await run(
                through: proxy,
                executor: .urlSession,
                authorization: .basic(username: "user", password: "pass"),
                destination: "socks-auth.example"
            )

            #expect(try outcome.result.get() == "Hello Through SOCKS")
            #expect(proxy.observations.requestedDestinations.first?.host == "socks-auth.example")
            #expect(
                proxy.observations.authenticationAttempts.first
                    == .init(username: Array("user".utf8), password: Array("pass".utf8), accepted: true)
            )
        }
    }

    @Test
    func socks_onURLSession_whenPasswordIsWrong_failsPromptly() async throws {
        let localServer = try await LocalServer(.standard)

        try await withProxy(credentials: .init(username: "user", password: "pass"), redirect: localServer.address) {
            proxy in
            let outcome = try await run(
                through: proxy,
                executor: .urlSession,
                authorization: .basic(username: "user", password: "WRONG"),
                destination: "socks-auth.example"
            )

            guard case .failure(let error) = outcome.result else {
                Issue.record("A wrong password was accepted")
                return
            }

            #expect(outcome.elapsed < 5)
            // The same typed error as under the NIO executors, with the `EAUTH` CFNetwork ended the
            // connection with as its cause.
            let typed = try #require(error as? ProxyAuthorizationError)
            #expect(typed.reason == .socksAuthenticationRejected)
            #expect(!String(describing: error).contains("WRONG"))
            #expect(!String(reflecting: error).contains("WRONG"))
            let underlying = try #require(typed.underlyingError as NSError?)
            #expect(underlying.domain == NSPOSIXErrorDomain)
            #expect(underlying.code == Int(EAUTH))
            #expect(proxy.observations.authenticationAttempts.map(\.accepted) == [false])
            #expect(proxy.connectAttempts.count == 0)
        }
    }

    /// The limit is on bytes, not characters: 127 two-byte characters and a letter are 255 bytes
    /// in 128 characters, which CFNetwork would cut; 127 of them are 254, which it carries.
    @Test
    func socks_onURLSession_limitIsCountedInBytes() async throws {
        let tooLong = String(repeating: "é", count: 127) + "p"
        let fits = String(repeating: "é", count: 127)

        #expect(tooLong.utf8.count == 255 && tooLong.count == 128)
        #expect(fits.utf8.count == 254)

        let refused = try await resolve(
            Proxy(
                host: "127.0.0.1",
                port: 1,
                connection: .socks,
                authorization: .basic(username: "u", password: tooLong)
            )
        )
        #expect(
            refused.session.configuration.urlSessionIncompatibilityReasons()
                == [.proxySOCKSCredentialsTooLongUnderURLSession]
        )

        let accepted = try await resolve(
            Proxy(
                host: "127.0.0.1",
                port: 1,
                connection: .socks,
                authorization: .basic(username: "u", password: fits)
            )
        )
        #expect(accepted.session.configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func socks_whenCredentialsAre254Bytes_urlSessionStaysAvailable() async throws {
        let username = String(repeating: "u", count: 254)

        let resolved = try await resolve(
            Proxy(
                host: "127.0.0.1",
                port: 1,
                connection: .socks,
                authorization: .basic(username: username, password: "p")
            )
        )

        #expect(resolved.session.configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    #endif
}

#endif
