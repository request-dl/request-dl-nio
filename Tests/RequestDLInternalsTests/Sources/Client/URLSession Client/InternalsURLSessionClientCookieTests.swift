//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Phase 5d of `URLSESSION_TASK.md`: the "required normalization" from URLSESSION_REPORT.md
/// §4.3. `URLSession` persists cookies in a jar by default (unlike the NIO
/// executor, which has none at all); `Internals.URLSessionClient.init` disables that explicitly
/// (`httpShouldSetCookies = false`, `httpCookieStorage = nil`) so which executor a session
/// resolves to never silently changes behavior across requests sharing that session.
///
/// `LocalServer.HTTPHandler` echoes back whatever `Cookie` header it actually received
/// (`HTTPResult.receivedCookieHeader`) -- the only way to prove the *second* request didn't
/// resend a cookie the *first* response set is to ask the server what it saw, not just what the
/// client sent (which this test has no independent way to inspect).
struct InternalsURLSessionClientCookieTests {

    @Test
    func execute_whenServerSetsCookie_secondRequestOnSameClientDoesNotResendIt() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let settingURI = "/" + UUID().uuidString
        let followingURI = "/" + UUID().uuidString

        localServer.cleanup(at: settingURI)
        localServer.cleanup(at: followingURI)

        localServer.insert(
            LocalServer.ResponseConfiguration(
                headers: ["Set-Cookie": "session=abc123; Path=/"],
                data: Data()
            ),
            at: settingURI
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: "no cookie here"),
            at: followingURI
        )

        defer {
            localServer.cleanup(at: settingURI)
            localServer.cleanup(at: followingURI)
        }

        // `URLSession`'s cookie jar (were it not disabled) is scoped to the session instance, so
        // both requests must share one client, not each get their own.
        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let delegate = AcceptAnyServerTrustDelegate()

        let settingURL = try #require(URL(string: "https://\(localServer.baseURL)\(settingURI)"))
        let followingURL = try #require(URL(string: "https://\(localServer.baseURL)\(followingURI)"))

        // When
        let settingResult = try await client.execute(request: URLRequest(url: settingURL), delegate: delegate)
        #expect(settingResult.head.status.code == 200)
        #expect(settingResult.head.headerValues(named: "Set-Cookie").first == "session=abc123; Path=/")

        let followingResult = try await client.execute(request: URLRequest(url: followingURL), delegate: delegate)

        // Then
        #expect(followingResult.head.status.code == 200)

        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: followingResult.body)
        #expect(decoded.receivedCookieHeader == nil)
    }
}

/// Test-only stand-in for the TLS challenge handling Phase 5e adds for real -- see the identical
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
