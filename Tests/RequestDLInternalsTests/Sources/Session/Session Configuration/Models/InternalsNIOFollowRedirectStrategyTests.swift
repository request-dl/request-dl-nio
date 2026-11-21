//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import NIOHTTP1
import Testing

@testable import RequestDLInternals

/// `Internals.NIOFollowRedirectStrategy` stands in for AsyncHTTPClient's own
/// `.follow(max:allowCycles:)`, so what is covered here is that it makes the decisions `.follow`
/// does (the limit, the cycle check, and the errors they fail with), plus the one it makes
/// differently on purpose: an explicit `Host` does not follow a redirect to another origin.
struct InternalsNIOFollowRedirectStrategyTests {

    // MARK: - Limit

    /// `.follow(max: 1, ...)` follows one redirect and fails the second.
    @Test
    func redirectDecision_whenWithinTheLimit_follows() throws {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 1, allowCycles: false)

        // When
        let decision = try strategy.redirectDecision(
            for: context(to: "https://example.com/b", history: ["https://example.com/a"])
        )

        // Then
        guard case .follow(let request) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(request.url == "https://example.com/b")
    }

    @Test
    func redirectDecision_whenPastTheLimit_failsWithRedirectLimitReached() {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 1, allowCycles: false)

        // When / Then
        #expect(throws: HTTPClientError.redirectLimitReached) {
            try strategy.redirectDecision(
                for: context(
                    to: "https://example.com/c",
                    history: ["https://example.com/a", "https://example.com/b"]
                )
            )
        }
    }

    @Test
    func redirectDecision_whenMaxIsZero_followsNothing() {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 0, allowCycles: false)

        // When / Then
        #expect(throws: HTTPClientError.redirectLimitReached) {
            try strategy.redirectDecision(
                for: context(to: "https://example.com/b", history: ["https://example.com/a"])
            )
        }
    }

    // MARK: - Cycles

    @Test
    func redirectDecision_whenRevisitingAURLAndCyclesAreNotAllowed_failsWithRedirectCycleDetected() {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 5, allowCycles: false)

        // When / Then
        #expect(throws: HTTPClientError.redirectCycleDetected) {
            try strategy.redirectDecision(
                for: context(
                    to: "https://example.com/a",
                    history: ["https://example.com/a", "https://example.com/b"]
                )
            )
        }
    }

    @Test
    func redirectDecision_whenRevisitingAURLAndCyclesAreAllowed_follows() throws {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 5, allowCycles: true)

        // When
        let decision = try strategy.redirectDecision(
            for: context(
                to: "https://example.com/a",
                history: ["https://example.com/a", "https://example.com/b"]
            )
        )

        // Then
        guard case .follow = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }
    }

    /// The limit is checked first, as `.follow` does, so a chain that is both too long and a cycle
    /// reports the limit.
    @Test
    func redirectDecision_whenBothTheLimitAndACycleApply_reportsTheLimit() {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 1, allowCycles: false)

        // When / Then
        #expect(throws: HTTPClientError.redirectLimitReached) {
            try strategy.redirectDecision(
                for: context(
                    to: "https://example.com/a",
                    history: ["https://example.com/a", "https://example.com/b"]
                )
            )
        }
    }

    // MARK: - Headers

    @Test
    func redirectDecision_whenRedirectLeavesTheOrigin_dropsTheHostHeader() throws {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 5, allowCycles: false)

        // When
        let decision = try strategy.redirectDecision(
            for: context(
                to: "https://other.example.com/b",
                history: ["https://example.com/a"],
                headers: ["Host": "api.internal", "X-Custom": "kept"]
            )
        )

        // Then
        guard case .follow(let request) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(!request.headers.contains(name: "Host"))
        #expect(request.headers.first(name: "X-Custom") == "kept")
    }

    @Test
    func redirectDecision_whenRedirectStaysOnTheOrigin_keepsTheHostHeader() throws {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(max: 5, allowCycles: false)

        // When
        let decision = try strategy.redirectDecision(
            for: context(
                to: "https://example.com/b",
                history: ["https://example.com/a"],
                headers: ["Host": "api.internal"]
            )
        )

        // Then
        guard case .follow(let request) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(request.headers.first(name: "Host") == "api.internal")
    }

    /// The leak behind the credential headers: a `Location` on the origin the previous hop went
    /// to keeps every credential in AsyncHTTPClient's own rewrite, and a path-scoped rule then maps
    /// it to another origin. What goes there must be what any redirect to another origin carries.
    @Test
    func redirectDecision_whenAPathScopedRuleMapsASameOriginLocationToAnotherOrigin_dropsTheCredentials() throws {
        // Given: `/v1` is not covered, `/v2` is, and goes to `mock.internal`.
        let strategy = Internals.NIOFollowRedirectStrategy(
            max: 5,
            allowCycles: false,
            urlOverrides: .init(rules: [
                .init(
                    origin: .init(scheme: "https", host: "api.example.com", port: nil, pathComponents: ["v2"]),
                    destination: .init(scheme: "https", host: "mock.internal", port: nil, pathComponents: [])
                )
            ])
        )

        // When: AsyncHTTPClient saw a same-origin redirect and kept everything.
        let decision = try strategy.redirectDecision(
            for: context(
                to: "https://api.example.com/v2/x",
                history: ["https://api.example.com/v1/x"],
                headers: [
                    "Authorization": "Bearer prod",
                    "Cookie": "s=1",
                    "Origin": "https://api.example.com",
                    "Proxy-Authorization": "Basic cHJveHk=",
                    "Host": "api.example.com",
                    "X-Custom": "kept",
                ]
            )
        )

        // Then
        guard case .follow(let request) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(request.url == "https://mock.internal/x")

        for name in Internals.RedirectSanitizer.crossOriginHeaders {
            #expect(!request.headers.contains(name: name), "\(name) reached another origin")
        }

        #expect(request.headers.first(name: "X-Custom") == "kept")
    }

    /// The other direction, which has to keep working: a `Location` that spells the host an
    /// override stands in for looks like another origin to AsyncHTTPClient, which took the
    /// credentials off, and is put back when the rewrite lands on the origin the previous hop
    /// went to.
    @Test
    func redirectDecision_whenTheRuleMapsALocationBackToThePreviousOrigin_keepsTheCredentialsItWasSent() throws {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(
            max: 5,
            allowCycles: false,
            urlOverrides: .init(rules: [
                .init(
                    origin: .init(scheme: "https", host: "staging.example.com", port: nil, pathComponents: []),
                    destination: .init(scheme: "http", host: "127.0.0.1", port: 8080, pathComponents: [])
                )
            ])
        )

        // When: the previous hop went to the mapped origin, the `Location` names the real one.
        var previous = HTTPClientRequest(url: "http://127.0.0.1:8080/a")
        previous.headers = ["Authorization": "Bearer t", "Cookie": "s=1"]

        var candidate = HTTPClientRequest(url: "https://staging.example.com/b")
        candidate.headers = ["X-Custom": "kept"]

        let decision = try strategy.redirectDecision(
            for: HTTPClientRedirectContext(
                redirectRequest: candidate,
                response: .init(version: .http1_1, status: .found),
                history: [
                    HTTPClientRequestResponse(
                        request: previous,
                        responseHead: .init(version: .http1_1, status: .found)
                    )
                ],
                redirectCount: 0
            )
        )

        // Then
        guard case .follow(let request) = decision else {
            Issue.record("Expected .follow, got \(decision)")
            return
        }

        #expect(request.url == "http://127.0.0.1:8080/b")
        #expect(request.headers.first(name: "Authorization") == "Bearer t")
        #expect(request.headers.first(name: "Cookie") == "s=1")
    }

    /// A rule covers the `Location` but the URL it maps to cannot be built: following it as the
    /// server wrote it would reach the host the rule stands in for.
    @Test
    func redirectDecision_whenARuleCoversTheLocationButItsDestinationCannotBeBuilt_failsInsteadOfFollowingIt() {
        // Given
        let strategy = Internals.NIOFollowRedirectStrategy(
            max: 5,
            allowCycles: false,
            urlOverrides: .init(rules: [
                .init(
                    origin: .init(scheme: "https", host: "staging.example.com", port: nil, pathComponents: []),
                    destination: .init(scheme: "https", host: "not a host", port: nil, pathComponents: [])
                )
            ])
        )

        // When / Then
        let error = #expect(throws: Internals.RedirectError.self) {
            try strategy.redirectDecision(
                for: context(
                    to: "https://staging.example.com/b",
                    history: ["https://staging.example.com/a"],
                    headers: ["Authorization": "Bearer prod"]
                )
            )
        }

        #expect(error?.reason == .invalidURL(nil))
    }

    // MARK: - Private methods

    private func context(
        to url: String,
        history: [String],
        headers: HTTPHeaders = [:]
    ) -> HTTPClientRedirectContext {
        var candidate = HTTPClientRequest(url: url)
        candidate.headers = headers

        return HTTPClientRedirectContext(
            redirectRequest: candidate,
            response: .init(version: .http1_1, status: .found),
            history: history.map {
                HTTPClientRequestResponse(
                    request: HTTPClientRequest(url: $0),
                    responseHead: .init(version: .http1_1, status: .found)
                )
            },
            redirectCount: history.count - 1
        )
    }
}

#endif
