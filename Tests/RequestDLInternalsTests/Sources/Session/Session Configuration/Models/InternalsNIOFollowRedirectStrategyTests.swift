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
