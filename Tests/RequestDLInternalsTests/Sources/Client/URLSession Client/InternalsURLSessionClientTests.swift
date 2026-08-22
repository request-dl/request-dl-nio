//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Internals-level counterpart to `RequestConfigurationURLSessionClientTests` (`RequestDLTests`):
/// exercises `Internals.URLSessionClient` directly, with a hand-built `URLRequest` rather than
/// one produced through `RequestConfiguration.buildURLRequest()` (a `RequestDL`-module type this
/// target does not depend on).
struct InternalsURLSessionClientTests {

    @Test
    func execute_whenRequestSucceeds_returnsHeadAndBody() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            headers: ["Content-Type": "application/json; charset=utf-8"],
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        #expect(result.head.status.code == 200)
        #expect(result.head.headerValues(named: "Content-Type").first == "application/json; charset=utf-8")

        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(decoded.response == output)
    }

    @Test
    func execute_whenMaximumConcurrentConnectionsSet_stillCompletesEveryRequest() async throws {
        // Given -- not a concurrency-gating assertion (that lives in
        // `InternalsThrottledExecutorTests`); just confirms the client wires the cap through
        // without breaking the request itself.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello Throttled World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            maximumConcurrentConnections: 1
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(decoded.response == output)
    }
}

/// Test-only stand-in for the TLS challenge handling Phase 5e adds for real -- see the identical
/// delegate in `RequestConfigurationURLSessionClientTests` (`RequestDLTests`) for why this exists
/// at all: `LocalServer` is always TLS-terminated with a throwaway self-signed certificate.
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
