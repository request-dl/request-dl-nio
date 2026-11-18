//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin) && canImport(NIOCore)

import Foundation
import Security

/// SOCKS5 username/password (RFC 1929) under `.urlSession`, through
/// `connectionProxyDictionary`'s `SOCKSUser`/`SOCKSPassword`: whether `URLSession` really
/// authenticates, shown against `LocalSOCKSProxy` (a real server that demands the credentials and
/// records the bytes it received), with negative controls (a wrong password fails, a proxy that
/// demands credentials refuses a client with none).
///
/// **Findings these tests pin down** (macOS; the keys are CFNetwork's, shared by every Apple
/// platform, but only macOS was run here):
/// - with the keys, `URLSession`'s greeting offers `00 02` (no authentication, or user/password) and
///   it then sends RFC 1929's sub-negotiation with the exact UTF-8 bytes; without them the greeting
///   offers `00` only;
/// - a wrong password fails the request at once with `NSPOSIXErrorDomain` 80 (`EAUTH`);
/// - an empty password and non-ASCII credentials work;
/// - a proxy that does not ask for authentication is used without the credentials;
/// - **CFNetwork cuts a username or a password at 254 bytes**, one short of RFC 1929's 255, so
///   255-byte credentials arrive damaged and are rejected. That is why
///   `Internals.ExecutorIncompatibilityReason.proxySOCKSCredentialsTooLongUnderURLSession` keeps
///   such a session off `.urlSession`.
///
/// The destination is not loopback, because macOS does not send loopback through a configured
/// proxy (see `InternalsURLSessionClientSOCKSProxyTests`); `LocalSOCKSProxy` is given a `redirect`
/// to the local server and dials that for whatever name the client asked for, so a real HTTPS
/// exchange completes through the tunnel.
struct InternalsURLSessionClientSOCKSAuthenticationTests {

    // MARK: - Private types

    private static let destinationName = "socks-auth.example"

    private struct Outcome {
        let body: Data?
        let error: (any Error)?
        let elapsed: TimeInterval
    }

    // MARK: - Private methods

    /// One HTTPS GET to `destinationName` through a SOCKS proxy at `proxy`, with `authorization`
    /// configured on the client.
    private func fetch(
        through proxy: LocalSOCKSProxy,
        authorization: Internals.Proxy.Authorization?
    ) async throws -> Outcome {
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello Through SOCKS"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            proxy: Internals.Proxy(host: proxy.host, port: proxy.port, connection: .socks, authorization: authorization)
        )

        let url = try #require(URL(string: "https://\(Self.destinationName)\(uri)"))
        let start = Date()

        do {
            let result = try await client.execute(
                request: URLRequest(url: url),
                delegate: AcceptAnyServerTrustDelegate()
            )

            return Outcome(body: result.body, error: nil, elapsed: Date().timeIntervalSince(start))
        } catch {
            return Outcome(body: nil, error: error, elapsed: Date().timeIntervalSince(start))
        }
    }

    private func assertDelivered(_ outcome: Outcome) throws {
        #expect(outcome.error == nil)
        let body = try #require(outcome.body)
        #expect(try JSONDecoder().decode(HTTPResult<String>.self, from: body).response == "Hello Through SOCKS")
    }

    // MARK: - Success

    @Test
    func urlSession_whenCredentialsMatch_authenticatesAndCarriesTraffic() async throws {
        // Given
        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: "user", password: "pass"),
            redirect: .init(host: "localhost", port: 8888)
        )

        // When
        let outcome = try await fetch(through: proxy, authorization: .socks(username: "user", password: "pass"))
        try await proxy.shutdown()

        // Then: it went through the proxy, which was asked for the name, not for loopback...
        try assertDelivered(outcome)
        #expect(proxy.observations.requestedDestinations.map(\.host) == [Self.destinationName])
        #expect(proxy.connectAttempts.count == 1)
        // ...offering user/password next to no authentication, and sent the exact bytes.
        #expect(proxy.observations.greetings == [[0x05, 0x02, 0x00, 0x02]])
        #expect(
            proxy.observations.authenticationAttempts
                == [.init(username: Array("user".utf8), password: Array("pass".utf8), accepted: true)]
        )
    }

    @Test
    func urlSession_whenPasswordIsEmpty_authenticates() async throws {
        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: "user", password: ""),
            redirect: .init(host: "localhost", port: 8888)
        )

        let outcome = try await fetch(through: proxy, authorization: .socks(username: "user", password: ""))
        try await proxy.shutdown()

        try assertDelivered(outcome)
        #expect(
            proxy.observations.authenticationAttempts == [
                .init(username: Array("user".utf8), password: [], accepted: true)
            ]
        )
    }

    @Test
    func urlSession_whenCredentialsAreNotASCII_sendsThemAsUTF8() async throws {
        let username = "usér😀"
        let password = "pässwörd:@%"

        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: username, password: password),
            redirect: .init(host: "localhost", port: 8888)
        )

        let outcome = try await fetch(through: proxy, authorization: .socks(username: username, password: password))
        try await proxy.shutdown()

        try assertDelivered(outcome)
        #expect(
            proxy.observations.authenticationAttempts
                == [.init(username: Array(username.utf8), password: Array(password.utf8), accepted: true)]
        )
    }

    @Test
    func urlSession_whenCredentialsAre254Bytes_authenticates() async throws {
        let username = String(repeating: "u", count: 254)
        let password = String(repeating: "p", count: 254)

        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: username, password: password),
            redirect: .init(host: "localhost", port: 8888)
        )

        let outcome = try await fetch(through: proxy, authorization: .socks(username: username, password: password))
        try await proxy.shutdown()

        try assertDelivered(outcome)
        #expect(proxy.observations.authenticationAttempts.first?.accepted == true)
    }

    /// RFC 1929 allows 255, `URLSession` sends 254 (measured), and the proxy, which has the real
    /// 255-byte credentials, rejects what it receives. The reason this configuration is kept off
    /// `.urlSession` (`urlSessionIncompatibilityReasons()`), and this test is the evidence for it:
    /// if an OS release stops cutting the credentials, it fails, and the reason can go.
    @Test
    func urlSession_whenCredentialsAre255Bytes_cfNetworkCutsThemAndTheProxyRejects() async throws {
        let username = String(repeating: "u", count: 255)
        let password = String(repeating: "p", count: 255)

        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: username, password: password),
            redirect: .init(host: "localhost", port: 8888)
        )

        let outcome = try await fetch(through: proxy, authorization: .socks(username: username, password: password))
        try await proxy.shutdown()

        #expect(outcome.error != nil)
        #expect(proxy.observations.authenticationAttempts.first?.username.count == 254)
        #expect(proxy.observations.authenticationAttempts.first?.password.count == 254)
        #expect(proxy.observations.authenticationAttempts.first?.accepted == false)
    }

    @Test
    func urlSession_whenProxyDoesNotRequireAuthentication_credentialsAreNotSent() async throws {
        let proxy = try await LocalSOCKSProxy.start(redirect: .init(host: "localhost", port: 8888))

        let outcome = try await fetch(through: proxy, authorization: .socks(username: "user", password: "pass"))
        try await proxy.shutdown()

        try assertDelivered(outcome)
        #expect(proxy.observations.greetings == [[0x05, 0x02, 0x00, 0x02]])
        #expect(proxy.observations.authenticationAttempts.isEmpty)
    }

    // MARK: - Failure

    @Test
    func urlSession_whenPasswordIsWrong_failsPromptlyWithoutReachingTheDestination() async throws {
        // Given
        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: "user", password: "pass"),
            redirect: .init(host: "localhost", port: 8888)
        )

        // When
        let outcome = try await fetch(through: proxy, authorization: .socks(username: "user", password: "WRONG"))
        try await Task.sleep(nanoseconds: 300_000_000)
        try await proxy.shutdown()

        // Then: the negative control of the tests above.
        let error = try #require(outcome.error)
        #expect(outcome.elapsed < 5)
        #expect((error as NSError).domain == NSPOSIXErrorDomain)
        #expect((error as NSError).code == Int(EAUTH))
        #expect(!String(describing: error).contains("WRONG"))
        #expect(proxy.observations.authenticationAttempts.count == 1)
        #expect(proxy.observations.authenticationAttempts.first?.accepted == false)
        #expect(proxy.connectAttempts.count == 0)
    }

    @Test
    func urlSession_whenProxyRequiresCredentialsAndNoneAreConfigured_fails() async throws {
        let proxy = try await LocalSOCKSProxy.start(
            credentials: .init(username: "user", password: "pass"),
            redirect: .init(host: "localhost", port: 8888)
        )

        let outcome = try await fetch(through: proxy, authorization: nil)
        try await proxy.shutdown()

        #expect(outcome.error != nil)
        #expect(outcome.elapsed < 5)
        // Without the keys the greeting offers no authentication only.
        #expect(proxy.observations.greetings == [[0x05, 0x01, 0x00]])
        #expect(proxy.observations.authenticationAttempts.isEmpty)
        #expect(proxy.connectAttempts.count == 0)
    }

    // MARK: - Configuration

    @Test(arguments: [
        Internals.Proxy.Authorization.basic(username: "u", password: "p"),
        .basicRawCredentials("dTpw"),
        .bearer(tokens: "t"),
        .socks(username: "", password: "p"),
        .socks(username: "u", password: String(repeating: "p", count: 256)),
    ])
    func urlSession_whenAuthorizationDoesNotFitASOCKSProxy_throwsInsteadOfDroppingIt(
        _ authorization: Internals.Proxy.Authorization
    ) {
        #expect(throws: Internals.Proxy.Authorization.Mismatch.self) {
            _ = try Internals.URLSessionClient(
                configuration: .ephemeral,
                proxy: Internals.Proxy(host: "127.0.0.1", port: 1, connection: .socks, authorization: authorization)
            )
        }
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling; see the identical
/// delegate in the other `Internals.URLSessionClient` test files for why this exists at all:
/// `LocalServer` is always TLS-terminated with a throwaway self-signed certificate.
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

#endif
