//
// See LICENSE for this package's licensing information.
//

import NIOConcurrencyHelpers
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Covers `.strategy` mode over `.urlSession`, plus the cross-origin header stripping shared by
/// both `.follow` and `.strategy` -- see the doc comment on `TaskDelegate.urlSession(_:task:
/// willPerformHTTPRedirection:newRequest:completionHandler:)`.
struct InternalsURLSessionClientRedirectStrategyTests {

    @Test
    func execute_whenRedirectCrossOrigin_stripsSensitiveHeadersBeforeStrategySees() async throws {
        // Given -- two different LocalServer ports count as two different origins.
        let origin = try await LocalServer(.standard)
        let destination = try await LocalServer(
            .init(host: "localhost", port: 8891, option: .none)
        )

        let originPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString
        let output = "Cross-origin redirect!"

        origin.cleanup(at: originPath)
        destination.cleanup(at: destinationPath)

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(destination.baseURL)\(destinationPath)"],
                data: Data()
            ),
            at: originPath
        )
        destination.insert(
            try LocalServer.ResponseConfiguration(jsonObject: output),
            at: destinationPath
        )

        defer {
            origin.cleanup(at: originPath)
            destination.cleanup(at: destinationPath)
        }

        let capturedContext = CapturedContext()

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .strategy(
                RecordingRedirectStrategy(capturedContext: capturedContext)
            )
        )

        var request = URLRequest(url: try #require(URL(string: "https://\(origin.baseURL)\(originPath)")))
        request.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")
        request.setValue("session=abc", forHTTPHeaderField: "Cookie")

        // When
        let result = try await client.execute(
            request: request,
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then -- the redirect went through to the cross-origin destination...
        #expect(result.head.status.code == 200)
        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(decoded.response == output)

        // ...but the strategy never saw the sensitive headers for the candidate request.
        let headers = try #require(capturedContext.context).redirectRequest.headers
        #expect(!headers.contains(name: "Authorization"))
        #expect(!headers.contains(name: "Cookie"))
    }

    /// - Note: Asserts on `Cookie` and a plain custom header, not `Authorization` --
    /// `URLSession` drops `Authorization` on *every* redirect it performs, same-origin included,
    /// as an OS-level default this type has no hook to override (confirmed empirically: swapping
    /// this test's header to `Authorization` fails even though nothing here strips it). That is
    /// strictly more conservative than the RFC 9110-derived, origin-only stripping this type adds
    /// on top for `Cookie`/`Origin`/`Proxy-Authorization`, so it is not a gap.
    @Test
    func execute_whenRedirectSameOrigin_preservesHeaders() async throws {
        // Given -- both hops on the same LocalServer, so same origin.
        let localServer = try await LocalServer(.standard)
        let originPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString

        localServer.cleanup(at: originPath)
        localServer.cleanup(at: destinationPath)

        localServer.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": destinationPath],
                data: Data()
            ),
            at: originPath
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: "Same origin!"),
            at: destinationPath
        )

        defer {
            localServer.cleanup(at: originPath)
            localServer.cleanup(at: destinationPath)
        }

        let capturedContext = CapturedContext()

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .strategy(
                RecordingRedirectStrategy(capturedContext: capturedContext)
            )
        )

        var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(originPath)")))
        request.setValue("session=abc", forHTTPHeaderField: "Cookie")
        request.setValue("hello", forHTTPHeaderField: "X-Custom-Header")

        // When
        _ = try await client.execute(
            request: request,
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        let headers = try #require(capturedContext.context).redirectRequest.headers
        #expect(headers.first(name: "Cookie") == "session=abc")
        #expect(headers.first(name: "X-Custom-Header") == "hello")
    }

    @Test
    func execute_whenStrategyReturnsDoNotFollow_returnsRedirectResponseWithoutFollowing() async throws {
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

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .strategy(DoNotFollowRedirectStrategy())
        )

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then -- the redirect response itself, not the destination.
        #expect(result.head.status.code == 302)
        #expect(result.head.headerValues(named: "Location").first == destination)
    }

    @Test
    func execute_whenStrategyThrows_propagatesAsRedirectError() async throws {
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

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .strategy(ThrowingRedirectStrategy())
        )

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))

        // When
        do {
            _ = try await client.execute(
                request: URLRequest(url: url),
                delegate: AcceptAnyServerTrustDelegate()
            )
            Issue.record("Not expecting success")
        } catch is ThrowingRedirectStrategy.SomeError {
            // Then -- expected
        }
    }
}

// MARK: - Test doubles

/// Synchronous by design -- `Internals.RedirectStrategy.redirectDecision(for:)` isn't `async`, so
/// capturing what it saw for later assertions must not go through anything that would let the
/// test read it before the callback (called from URLSession's own delegate queue) has finished.
private final class CapturedContext: Sendable {

    private let box = NIOLockedValueBox<Internals.RedirectContext?>(nil)

    var context: Internals.RedirectContext? {
        box.withLockedValue { $0 }
    }

    func record(_ context: Internals.RedirectContext) {
        box.withLockedValue { $0 = context }
    }
}

private struct RecordingRedirectStrategy: Internals.RedirectStrategy {

    let capturedContext: CapturedContext

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        capturedContext.record(context)
        return .follow(context.redirectRequest)
    }
}

private struct DoNotFollowRedirectStrategy: Internals.RedirectStrategy {

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        .doNotFollow
    }
}

private struct ThrowingRedirectStrategy: Internals.RedirectStrategy {

    struct SomeError: Error {}

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        throw SomeError()
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling -- see the identical
/// delegate in `InternalsURLSessionClientRedirectTests`/`InternalsURLSessionClientTests` for why
/// this exists at all: `LocalServer` is always TLS-terminated with a throwaway self-signed
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
