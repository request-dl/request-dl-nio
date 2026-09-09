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

    /// `execute(request:delegate:)` bridges `dataTask(with:)` to `async`/`await` by hand
    /// (`session.data(for:delegate:)` has a confirmed crash under load -- see the method's own
    /// doc comment) -- unlike that Foundation API, nothing cancels the underlying
    /// `URLSessionTask` for free just because the awaiting Swift `Task` was cancelled. This
    /// confirms `CancellableTaskBox` actually restores that: cancelling the caller's `Task` both
    /// makes the call throw and stops the real network request, not just the first of the two.
    @Test
    func execute_whenTaskCancelledMidFlight_cancelsUnderlyingURLSessionTaskAndThrows() async throws {
        try await withHangingServer { port in
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))

            let responseTask = _Concurrency.Task {
                try await client.execute(request: URLRequest(url: url))
            }

            // Gives the request a moment to actually reach the (unresponsive) server before
            // cancelling, so this exercises a genuine in-flight cancellation rather than one
            // that races the connection attempt itself.
            try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            #expect(client.isRunning)

            responseTask.cancel()

            await #expect(throws: (any Error).self) {
                _ = try await responseTask.value
            }

            // `didCompleteWithError:` releases the operation-queue slot asynchronously, so poll
            // briefly rather than asserting immediately after `cancel()` returns.
            var stillRunning = client.isRunning
            for _ in 0..<50 where stillRunning {
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                stillRunning = client.isRunning
            }
            #expect(!stillRunning)
        }
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling -- see the identical
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
