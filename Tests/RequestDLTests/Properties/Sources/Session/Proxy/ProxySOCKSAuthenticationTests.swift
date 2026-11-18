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
import struct Foundation.UUID
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
        let elapsed: Duration
    }

    // MARK: - Private methods

    /// Runs one `DataTask` through `proxy` and reports its outcome.
    private func run(
        through proxy: LocalSOCKSProxy,
        executor: Session.Executor = .nio,
        authorization: ProxyAuthorization?
    ) async throws -> Outcome {
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello Through SOCKS"), at: uri)

        let session = Session.localServer.requiredExecutor(executor)
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let data = try await DataTask {
                BaseURL(localServer.baseURL)
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
            }
            .extractPayload()
            .result()

            localServer.cleanup(at: uri)

            return Outcome(
                result: .success(try HTTPResult<String>(data).response),
                elapsed: start.duration(to: clock.now)
            )
        } catch {
            localServer.cleanup(at: uri)
            return Outcome(result: .failure(error), elapsed: start.duration(to: clock.now))
        }
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
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: "user", password: "pass"))
        defer { Task { try? await proxy.shutdown() } }

        // When
        let outcome = try await run(through: proxy, executor: executor, authorization: .basic(username: "user", password: "pass"))

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

    @Test
    func socks_whenPasswordIsEmpty_authenticates() async throws {
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: "user", password: ""))
        defer { Task { try? await proxy.shutdown() } }

        let outcome = try await run(through: proxy, authorization: .basic(username: "user", password: ""))

        #expect(try outcome.result.get() == "Hello Through SOCKS")
        #expect(proxy.observations.authenticationAttempts == [.init(username: Array("user".utf8), password: [], accepted: true)])
    }

    @Test
    func socks_whenCredentialsAreNotASCII_sendsThemAsUTF8() async throws {
        let username = "usér😀"
        let password = "pässwörd:@%"
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: username, password: password))
        defer { Task { try? await proxy.shutdown() } }

        let outcome = try await run(through: proxy, authorization: .basic(username: username, password: password))

        #expect(try outcome.result.get() == "Hello Through SOCKS")
        #expect(
            proxy.observations.authenticationAttempts
                == [.init(username: Array(username.utf8), password: Array(password.utf8), accepted: true)]
        )
    }

    @Test
    func socks_whenCredentialsAreExactly255Bytes_authenticates() async throws {
        let username = String(repeating: "u", count: 255)
        let password = String(repeating: "é", count: 127) + "p"
        #expect(password.utf8.count == 255)

        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: username, password: password))
        defer { Task { try? await proxy.shutdown() } }

        let outcome = try await run(through: proxy, authorization: .basic(username: username, password: password))

        #expect(try outcome.result.get() == "Hello Through SOCKS")
        #expect(proxy.observations.authenticationAttempts.first?.username.count == 255)
        #expect(proxy.observations.authenticationAttempts.first?.password.count == 255)
    }

    @Test
    func socks_whenProxyDoesNotRequireAuthentication_credentialsAreNotSent() async throws {
        // Given: a proxy that takes no authentication, and credentials configured anyway.
        let proxy = try await LocalSOCKSProxy.start()
        defer { Task { try? await proxy.shutdown() } }

        // When
        let outcome = try await run(through: proxy, authorization: .basic(username: "user", password: "pass"))

        // Then: it works, and the credentials never left.
        #expect(try outcome.result.get() == "Hello Through SOCKS")
        #expect(proxy.observations.authenticationAttempts.isEmpty)
        #expect(proxy.observations.greetings.first?.contains(0x00) == true)
    }

    // MARK: - Failure

    @Test(arguments: executors)
    func socks_whenPasswordIsWrong_failsPromptlyAndIsNotRetried(_ executor: Session.Executor) async throws {
        // Given
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: "user", password: "pass"))
        defer { Task { try? await proxy.shutdown() } }

        // When
        let outcome = try await run(through: proxy, executor: executor, authorization: .basic(username: "user", password: "WRONG"))

        // Then
        let error = try #require({ () -> (any Error)? in
            if case .failure(let error) = outcome.result { return error }
            return nil
        }())

        #expect(outcome.elapsed < .seconds(5))
        // The proxy was asked once and rejected: nothing retried the same wrong credentials.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(proxy.observations.authenticationAttempts.count == 1)
        #expect(proxy.observations.authenticationAttempts.first?.accepted == false)
        #expect(proxy.connectAttempts.count == 0)
        // The error says what happened, and not what the password was.
        #expect(String(describing: error).contains("uthentication"))
        #expect(!String(describing: error).contains("WRONG"))
    }

    @Test
    func socks_whenProxyRequiresCredentialsAndNoneAreConfigured_failsPromptly() async throws {
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: "user", password: "pass"))
        defer { Task { try? await proxy.shutdown() } }

        let outcome = try await run(through: proxy, authorization: nil)

        guard case .failure = outcome.result else {
            Issue.record("A proxy that needs credentials was used without any")
            return
        }

        #expect(outcome.elapsed < .seconds(5))
        #expect(proxy.observations.authenticationAttempts.isEmpty)
        #expect(proxy.connectAttempts.count == 0)
    }

    @Test(arguments: [
        ProxyAuthorization.bearer(tokens: "token"),
        ProxyAuthorization.basic(credentials: "dXNlcjpwYXNz"),
    ])
    func socks_whenAuthorizationIsAnHTTPHeader_throwsBeforeConnecting(_ authorization: ProxyAuthorization) async throws {
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: "user", password: "pass"))
        defer { Task { try? await proxy.shutdown() } }

        let outcome = try await run(through: proxy, authorization: authorization)

        guard case .failure(let error) = outcome.result else {
            Issue.record("An HTTP authorization header was accepted by a SOCKS proxy")
            return
        }

        #expect((error as? ProxyAuthorizationError)?.reason == .socksRequiresUsernameAndPassword)
        #expect(proxy.observations.greetings.isEmpty)
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
        let proxy = try await LocalSOCKSProxy.start(credentials: .init(username: "user", password: "pass"))
        defer { Task { try? await proxy.shutdown() } }

        let outcome = try await run(through: proxy, authorization: .basic(username: username, password: password))

        guard case .failure(let error) = outcome.result else {
            Issue.record("Out of range credentials were accepted")
            return
        }

        #expect((error as? ProxyAuthorizationError)?.reason == expected)
        #expect(proxy.observations.greetings.isEmpty)
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

            Proxy(host: "127.0.0.1", port: 1, connection: .socks, authorization: .basic(username: username, password: "p"))
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
            Proxy(host: "127.0.0.1", port: 1, connection: .socks, authorization: .basic(username: username, password: "p"))
        )

        #expect(resolved.session.configuration.resolveExecutor() != .urlSession)
    }

    @Test
    func socks_whenCredentialsAre254Bytes_urlSessionStaysAvailable() async throws {
        let username = String(repeating: "u", count: 254)

        let resolved = try await resolve(
            Proxy(host: "127.0.0.1", port: 1, connection: .socks, authorization: .basic(username: username, password: "p"))
        )

        #expect(resolved.session.configuration.urlSessionIncompatibilityReasons().isEmpty)
    }

    #endif
}

#endif
