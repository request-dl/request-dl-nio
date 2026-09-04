//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import Testing

@testable import RequestDLInternals

/// Covers `Internals.NIORedirectStrategyAdapter`'s conversions in isolation, without a real
/// network round trip -- the strategy mechanism itself (rewriting a redirect request, refusing
/// one, detecting cycles via history, a strategy that throws) is AsyncHTTPClient's own, covered
/// by its own test suite; what's authored here, and worth its own coverage, is the mapping to and
/// from `Internals.RedirectContext`/`RedirectRequest`/`RedirectDecision`.
struct InternalsNIORedirectStrategyAdapterTests {

    @Test
    func redirectDecision_whenFollowing_onlyOverridesURLMethodAndHeaders() throws {
        // Given -- a candidate request AsyncHTTPClient already built, carrying a body the
        // strategy never touches.
        var candidateRequest = HTTPClientRequest(url: "https://example.com/redirected")
        candidateRequest.method = .GET
        candidateRequest.headers = ["X-Original": "kept-unless-overwritten"]
        candidateRequest.body = .bytes(ByteBuffer(string: "original body"))

        let strategy = RecordingStrategy { context in
            var request = context.redirectRequest
            request.url = "https://example.com/adjusted"
            request.method = "POST"
            request.headers = .init([("X-Adjusted", "yes")])
            return .follow(request)
        }

        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        let context = HTTPClientRedirectContext(
            redirectRequest: candidateRequest,
            response: .init(version: .http1_1, status: .found),
            history: [
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: "https://example.com/original"),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            ],
            redirectCount: 0
        )

        // When
        let decision = try adapter.redirectDecision(for: context)

        // Then
        guard case .follow(let resultingRequest) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(resultingRequest.url == "https://example.com/adjusted")
        #expect(resultingRequest.method == .POST)
        #expect(resultingRequest.headers.first(name: "X-Adjusted") == "yes")
        // Body -- untouched, since `Internals.RedirectRequest` has no way to replace it.
        #expect(resultingRequest.body != nil)

        // The strategy saw the candidate's own url/method/headers, unmodified.
        let seenRequest = try #require(strategy.seenContext).redirectRequest
        #expect(seenRequest.url == "https://example.com/redirected")
        #expect(seenRequest.headers.first(name: "X-Original") == "kept-unless-overwritten")
        #expect(seenRequest.hasBody)

        // ...and the full history, correctly mapped.
        let seenHistory = try #require(strategy.seenContext).history
        #expect(seenHistory.count == 1)
        #expect(seenHistory[0].request.url == "https://example.com/original")
    }

    @Test
    func redirectDecision_whenDoNotFollow_passesThrough() throws {
        // Given
        let strategy = RecordingStrategy { _ in .doNotFollow }
        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        let context = HTTPClientRedirectContext(
            redirectRequest: HTTPClientRequest(url: "https://example.com/redirected"),
            response: .init(version: .http1_1, status: .found),
            history: [],
            redirectCount: 0
        )

        // When
        let decision = try adapter.redirectDecision(for: context)

        // Then
        guard case .doNotFollow = decision else {
            Issue.record("Expected .doNotFollow, got \(decision)")
            return
        }
    }

    @Test
    func redirectDecision_whenStrategyThrows_propagates() {
        // Given
        struct SomeError: Error {}
        let strategy = RecordingStrategy { _ -> Internals.RedirectDecision in throw SomeError() }
        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        let context = HTTPClientRedirectContext(
            redirectRequest: HTTPClientRequest(url: "https://example.com/redirected"),
            response: .init(version: .http1_1, status: .found),
            history: [],
            redirectCount: 0
        )

        // When / Then
        #expect(throws: SomeError.self) {
            try adapter.redirectDecision(for: context)
        }
    }
}

// MARK: - Test doubles

private final class RecordingStrategy: Internals.RedirectStrategy, @unchecked Sendable {

    let handler: (Internals.RedirectContext) throws -> Internals.RedirectDecision
    private(set) var seenContext: Internals.RedirectContext?

    init(handler: @escaping (Internals.RedirectContext) throws -> Internals.RedirectDecision) {
        self.handler = handler
    }

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        seenContext = context
        return try handler(context)
    }
}
