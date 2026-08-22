//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Phase 5b of `URLSESSION_TASK.md`: `Internals.RedirectConfiguration` enforced by hand over
/// `.urlSession`, since URLSession has no native "max redirects" / "allow cycles" concept.
///
/// There was no pre-existing NIO-backend redirect round-trip suite to port from -- only unit
/// tests for `Internals.RedirectConfiguration.build()`'s mapping and the `Session.enableRedirect`/
/// `disableRedirect` modifiers existed. These assertions are instead derived directly from
/// AsyncHTTPClient's own `RedirectState.redirect(to:)` (vendored in `async-http-client`,
/// `RedirectState.swift`), which `RedirectEnforcingURLSessionTaskDelegate` ports: `visited` starts
/// at `[initialURL]`, a redirect is refused once `visited.count > max`, and cycle detection
/// compares the target against every URL visited so far, including the initial one.
struct InternalsURLSessionClientRedirectTests {

    @Test
    func execute_whenRedirectWithinLimit_followsToFinalDestination() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString
        let output = "Redirected!"

        localServer.cleanup(at: origin)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": destination],
                data: Data()
            ),
            at: origin
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: output),
            at: destination
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .follow(max: 5, allowCycles: false)
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        #expect(result.head.status.code == 200)

        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(decoded.response == output)
    }

    @Test
    func execute_whenRedirectChainExceedsMax_throwsRedirectLimitReachedError() async throws {
        // Given -- two redirects (origin -> hop -> destination) against a client only willing to
        // follow one.
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let hop = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString

        localServer.cleanup(at: origin)
        localServer.cleanup(at: hop)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": hop], data: Data()),
            at: origin
        )
        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: hop
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: "unreachable"),
            at: destination
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: hop)
            localServer.cleanup(at: destination)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .follow(max: 1, allowCycles: false)
        )

        // When
        do {
            _ = try await client.execute(
                request: URLRequest(url: url),
                delegate: AcceptAnyServerTrustDelegate()
            )
            Issue.record("Not expecting success")
        } catch is Internals.URLSessionClient.RedirectLimitReachedError {
            // Then -- expected
        }
    }

    @Test
    func execute_whenRedirectRevisitsURL_throwsRedirectCycleDetectedError() async throws {
        // Given -- origin -> hop -> origin, a two-hop cycle back to the first URL visited.
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let hop = "/" + UUID().uuidString

        localServer.cleanup(at: origin)
        localServer.cleanup(at: hop)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": hop], data: Data()),
            at: origin
        )
        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": origin], data: Data()),
            at: hop
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: hop)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .follow(max: 5, allowCycles: false)
        )

        // When
        do {
            _ = try await client.execute(
                request: URLRequest(url: url),
                delegate: AcceptAnyServerTrustDelegate()
            )
            Issue.record("Not expecting success")
        } catch is Internals.URLSessionClient.RedirectCycleDetectedError {
            // Then -- expected
        }
    }

    @Test
    func execute_whenRedirectAllowsCycles_followsBackToAVisitedURL() async throws {
        // Given -- a two-hop cycle (origin -> hop -> origin -> ...), same URIs as the cycle test
        // above, but with `allowCycles: true`.
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let hop = "/" + UUID().uuidString

        localServer.cleanup(at: origin)
        localServer.cleanup(at: hop)

        // `LocalServer.ResponseQueue` hands out one queued response per hit, most-recently-
        // inserted first, then falls back to a bare `.ok` once exhausted -- unlike the other
        // redirect tests here, this chain actually revisits both URIs for real (that is the
        // point: `allowCycles: true` means the redirect is *followed*, not just permitted in the
        // abstract), so each needs as many queued copies as it is genuinely re-fetched: origin is
        // requested at redirects 0 and 2, hop at redirects 1 and 3 -- two hits apiece before the
        // chain fails on the count, not the revisit.
        for _ in 0..<2 {
            localServer.insert(
                LocalServer.ResponseConfiguration(status: .found, headers: ["Location": hop], data: Data()),
                at: origin
            )
            localServer.insert(
                LocalServer.ResponseConfiguration(status: .found, headers: ["Location": origin], data: Data()),
                at: hop
            )
        }

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: hop)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .follow(max: 3, allowCycles: true)
        )

        // When -- origin -> hop -> origin -> hop is 3 redirects, exactly at `max`; a 4th would
        // still be within `allowCycles: true`'s revisit tolerance but would exceed `max`, so the
        // chain must fail with the limit, not the cycle, error, proving `allowCycles` actually
        // suppressed cycle detection rather than the chain never revisiting anything.
        do {
            _ = try await client.execute(
                request: URLRequest(url: url),
                delegate: AcceptAnyServerTrustDelegate()
            )
            Issue.record("Not expecting success")
        } catch is Internals.URLSessionClient.RedirectLimitReachedError {
            // Then -- expected: cycles are tolerated, only the count still gates it
        }
    }

    @Test
    func execute_whenDisallowed_returnsRedirectResponseWithoutFollowing() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString

        localServer.cleanup(at: origin)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: origin
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .disallow
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then -- the redirect response itself, not an error and not the destination.
        #expect(result.head.status.code == 302)
        #expect(result.head.headerValues(named: "Location").first == destination)
    }
}

/// Test-only stand-in for the TLS challenge handling Phase 5e adds for real -- see the identical
/// delegate in `InternalsURLSessionClientTests`/`RequestConfigurationURLSessionClientTests` for
/// why this exists at all: `LocalServer` is always TLS-terminated with a throwaway self-signed
/// certificate, on every hop of a redirect chain, not only the first request.
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
