//
// See LICENSE for this package's licensing information.
//

// `Internals.NIORedirectStrategyAdapter` (and AsyncHTTPClient's own `HTTPClientRequest`/
// `HTTPClientRedirectContext` it adapts between) only exist under `canImport(NIOCore)`.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import Testing

@testable import RequestDLInternals

/// Covers `Internals.NIORedirectStrategyAdapter`'s conversions in isolation, without a real
/// network round trip. The strategy mechanism itself (rewriting a redirect request, refusing
/// one, detecting cycles via history, a strategy that throws) is AsyncHTTPClient's own, covered
/// by its own test suite; what's authored here, and worth its own coverage, is the mapping to and
/// from `Internals.RedirectContext`/`RedirectRequest`/`RedirectDecision`.
struct InternalsNIORedirectStrategyAdapterTests {

    @Test
    func redirectDecision_whenFollowing_onlyOverridesURLMethodAndHeaders() throws {
        // Given: a candidate request AsyncHTTPClient already built, carrying a body the
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
        // Body: untouched, since `Internals.RedirectRequest` has no way to replace it.
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

    // MARK: - Cross-origin headers

    @Test
    func redirectDecision_whenRedirectLeavesTheOrigin_doesNotHandTheStrategyAHostHeader() throws {
        // Given: AsyncHTTPClient strips the credentials for another origin, but not `Host`.
        var candidateRequest = HTTPClientRequest(url: "https://other.example.com/redirected")
        candidateRequest.headers = ["Host": "api.internal", "X-Original": "kept"]

        let strategy = RecordingStrategy { context in .follow(context.redirectRequest) }
        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        // When
        let decision = try adapter.redirectDecision(
            for: context(candidateRequest, from: "https://example.com/original")
        )

        // Then
        let seenHeaders = try #require(strategy.seenContext).redirectRequest.headers
        #expect(!seenHeaders.contains(name: "Host"))
        #expect(seenHeaders.first(name: "X-Original") == "kept")

        guard case .follow(let resultingRequest) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(!resultingRequest.headers.contains(name: "Host"))
    }

    @Test
    func redirectDecision_whenRedirectStaysOnTheOrigin_keepsTheHostHeader() throws {
        // Given
        var candidateRequest = HTTPClientRequest(url: "https://example.com/redirected")
        candidateRequest.headers = ["Host": "api.internal", "Cookie": "session=abc"]

        let strategy = RecordingStrategy { context in .follow(context.redirectRequest) }
        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        // When
        let decision = try adapter.redirectDecision(
            for: context(candidateRequest, from: "https://example.com/original")
        )

        // Then
        guard case .follow(let resultingRequest) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(resultingRequest.headers.first(name: "Host") == "api.internal")
        #expect(resultingRequest.headers.first(name: "Cookie") == "session=abc")
    }

    /// The strategy saw a same-origin candidate, `Cookie` and all, and moved it to another origin:
    /// nothing had checked the URL it answered with.
    @Test
    func redirectDecision_whenTheStrategyMovesTheRedirectToAnotherOrigin_stripsWhatDoesNotBelongThere() throws {
        // Given
        var candidateRequest = HTTPClientRequest(url: "https://example.com/redirected")
        candidateRequest.headers = [
            "Host": "api.internal",
            "Cookie": "session=abc",
            "Authorization": "Bearer secret",
            "Origin": "https://example.com",
            "Proxy-Authorization": "Basic secret",
            "X-Custom": "kept",
        ]

        let strategy = RecordingStrategy { context in
            var request = context.redirectRequest
            request.url = "https://other.example.com/moved"
            return .follow(request)
        }

        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        // When
        let decision = try adapter.redirectDecision(
            for: context(candidateRequest, from: "https://example.com/original")
        )

        // Then
        let seenHeaders = try #require(strategy.seenContext).redirectRequest.headers
        #expect(seenHeaders.first(name: "Cookie") == "session=abc")

        guard case .follow(let resultingRequest) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(resultingRequest.url == "https://other.example.com/moved")

        for name in ["Host", "Cookie", "Authorization", "Origin", "Proxy-Authorization"] {
            #expect(!resultingRequest.headers.contains(name: name), "\(name) must not follow to another origin")
        }

        #expect(resultingRequest.headers.first(name: "X-Custom") == "kept")
    }

    /// A strategy that adds credentials of its own for the origin it sends the request to is the
    /// one thing this takes away: the rule is on the origin, not on who put the header there.
    @Test
    func redirectDecision_whenTheStrategyAddsACredentialForAnotherOrigin_stripsItToo() throws {
        // Given
        let strategy = RecordingStrategy { context in
            var request = context.redirectRequest
            request.url = "https://other.example.com/moved"
            request.headers = .init([("Authorization", "Bearer for-other")])
            return .follow(request)
        }

        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        // When
        let decision = try adapter.redirectDecision(
            for: context(
                HTTPClientRequest(url: "https://example.com/redirected"),
                from: "https://example.com/original"
            )
        )

        // Then
        guard case .follow(let resultingRequest) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(!resultingRequest.headers.contains(name: "Authorization"))
    }

    // MARK: - Private methods

    private func context(_ candidate: HTTPClientRequest, from previousURL: String) -> HTTPClientRedirectContext {
        HTTPClientRedirectContext(
            redirectRequest: candidate,
            response: .init(version: .http1_1, status: .found),
            history: [
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: previousURL),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            ],
            redirectCount: 0
        )
    }
}

// MARK: - Test doubles

extension InternalsNIORedirectStrategyAdapterTests {

    /// A strategy's method is written on the request line as it is (`.RAW(value:)`).
    @Test
    func redirectDecision_whenFollowingWithAMethodThatIsNotAToken_throws() throws {
        let strategy = RecordingStrategy { context in
            var request = context.redirectRequest
            request.method = "GET / HTTP/1.1\r\nX: y\r\n\r\nPOST"
            return .follow(request)
        }

        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        let context = HTTPClientRedirectContext(
            redirectRequest: HTTPClientRequest(url: "https://example.com/redirected"),
            response: .init(version: .http1_1, status: .found),
            history: [
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: "https://example.com/original"),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            ],
            redirectCount: 0
        )

        #expect(throws: Internals.InvalidMethodError.self) {
            try adapter.redirectDecision(for: context)
        }
    }

    /// A strategy's headers are no more trusted than the caller's, and the error for a rejected
    /// one must not carry the value: AsyncHTTPClient's own does.
    @Test
    func redirectDecision_whenFollowingWithAHeaderValueThatIsNotValid_throwsWithoutTheValue() throws {
        let strategy = RecordingStrategy { context in
            var request = context.redirectRequest
            request.headers.add(name: "X-Token", value: "s3cr3t\u{0000}token")
            return .follow(request)
        }

        let adapter = Internals.NIORedirectStrategyAdapter(strategy: strategy)

        let context = HTTPClientRedirectContext(
            redirectRequest: HTTPClientRequest(url: "https://example.com/redirected"),
            response: .init(version: .http1_1, status: .found),
            history: [
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: "https://example.com/original"),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            ],
            redirectCount: 0
        )

        let error = #expect(throws: Internals.InvalidHeaderError.self) {
            try adapter.redirectDecision(for: context)
        }

        #expect(error == Internals.InvalidHeaderError(.value, count: 1, headerNames: ["X-Token"]))
        #expect(!String(describing: error).contains("s3cr3t"))
    }

    /// A rule covers the `Location` but the URL it maps to cannot be built: the strategy is not
    /// consulted, and the redirect is not followed to the host the rule stands in for.
    @Test
    func redirectDecision_whenARuleCoversTheLocationButItsDestinationCannotBeBuilt_failsWithoutConsultingTheStrategy() {
        let strategy = RecordingStrategy { context in .follow(context.redirectRequest) }

        let adapter = Internals.NIORedirectStrategyAdapter(
            strategy: strategy,
            urlOverrides: .init(rules: [
                .init(
                    origin: .init(scheme: "https", host: "staging.example.com", port: nil, pathComponents: []),
                    destination: .init(scheme: "https", host: "not a host", port: nil, pathComponents: [])
                )
            ])
        )

        let context = HTTPClientRedirectContext(
            redirectRequest: HTTPClientRequest(url: "https://staging.example.com/b"),
            response: .init(version: .http1_1, status: .found),
            history: [
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: "https://staging.example.com/a"),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            ],
            redirectCount: 0
        )

        let error = #expect(throws: Internals.RedirectError.self) {
            try adapter.redirectDecision(for: context)
        }

        #expect(error?.reason == .invalidURL(nil))
        #expect(strategy.seenContext == nil)
    }

    /// The URL the strategy answers with is mapped through the rules like any other `Location`.
    @Test
    func redirectDecision_whenTheStrategyAnswersWithAURLWhoseRuleDestinationCannotBeBuilt_fails() {
        let strategy = RecordingStrategy { context in
            var request = context.redirectRequest
            request.url = "https://staging.example.com/c"
            return .follow(request)
        }

        let adapter = Internals.NIORedirectStrategyAdapter(
            strategy: strategy,
            urlOverrides: .init(rules: [
                .init(
                    origin: .init(scheme: "https", host: "staging.example.com", port: nil, pathComponents: []),
                    destination: .init(scheme: "https", host: "not a host", port: nil, pathComponents: [])
                )
            ])
        )

        let context = HTTPClientRedirectContext(
            redirectRequest: HTTPClientRequest(url: "https://other.example.com/b"),
            response: .init(version: .http1_1, status: .found),
            history: [
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: "https://other.example.com/a"),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            ],
            redirectCount: 0
        )

        #expect(throws: Internals.RedirectError.self) {
            try adapter.redirectDecision(for: context)
        }
    }
}

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

#endif
