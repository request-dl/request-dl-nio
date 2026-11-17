//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsURLOverridesTests {

    // MARK: - Helpers

    private func endpoint(
        _ scheme: String,
        _ host: String,
        port: Int? = nil,
        path: [String] = []
    ) -> Internals.URLOverrides.Endpoint {
        .init(scheme: scheme, host: host, port: port, pathComponents: path)
    }

    private func overrides(
        _ pairs: (Internals.URLOverrides.Endpoint, Internals.URLOverrides.Endpoint)...
    ) -> Internals.URLOverrides {
        .init(rules: pairs.map { .init(origin: $0.0, destination: $0.1) })
    }

    // MARK: - rewriting

    @Test
    func rewriting_whenAWholeHostRuleCoversTheURL_replacesSchemeHostAndPortAndKeepsTheRest() {
        // Given
        let overrides = overrides(
            (endpoint("https", "staging.example.test"), endpoint("http", "127.0.0.1", port: 8080))
        )

        // When
        let url = overrides.rewriting("https://staging.example.test/a/b/?x=1&y=2#top")

        // Then
        #expect(url == "http://127.0.0.1:8080/a/b/?x=1&y=2#top")
    }

    @Test
    func rewriting_whenThePathIsScoped_replacesTheMatchedPrefixByComponent() {
        // Given
        let overrides = overrides(
            (endpoint("https", "staging.example.test", path: ["api", "v1"]), endpoint("https", "new.example.test", path: ["v2"]))
        )

        // When / Then
        #expect(overrides.rewriting("https://staging.example.test/api/v1/users") == "https://new.example.test/v2/users")
        #expect(overrides.rewriting("https://staging.example.test/api/v1") == "https://new.example.test/v2")
        #expect(overrides.rewriting("https://staging.example.test/api/v10/users") == nil)
        #expect(overrides.rewriting("https://staging.example.test/other") == nil)
    }

    @Test
    func rewriting_whenNoRuleCovers_returnsNil() {
        // Given
        let overrides = overrides((endpoint("https", "staging.example.test"), endpoint("https", "real.example.test")))

        // When / Then: another host, another scheme and another port are other origins.
        #expect(overrides.rewriting("https://other.example.test/a") == nil)
        #expect(overrides.rewriting("http://staging.example.test/a") == nil)
        #expect(overrides.rewriting("https://staging.example.test:8443/a") == nil)
        #expect(overrides.rewriting("/relative") == nil)
        #expect(Internals.URLOverrides().rewriting("https://staging.example.test/a") == nil)
    }

    @Test
    func rewriting_comparesTheOriginTheWayAResolvedRequestIs() {
        // Given
        let overrides = overrides((endpoint("https", "Staging.Example.Test"), endpoint("https", "real.example.test")))

        // When / Then: the host is case insensitive, and the default port is the one left out.
        #expect(overrides.rewriting("HTTPS://staging.example.test:443/a") == "https://real.example.test/a")
    }

    @Test
    func rewriting_whenSeveralRulesCover_theMostSpecificWinsThenTheLastDeclared() {
        // Given
        let host = endpoint("https", "staging.example.test")
        let scoped = endpoint("https", "staging.example.test", path: ["api"])

        let overrides = overrides(
            (scoped, endpoint("https", "scoped.example.test")),
            (host, endpoint("https", "first.example.test")),
            (host, endpoint("https", "last.example.test"))
        )

        // When / Then
        #expect(overrides.rewriting("https://staging.example.test/api/x") == "https://scoped.example.test/x")
        #expect(overrides.rewriting("https://staging.example.test/x") == "https://last.example.test/x")
    }

    @Test
    func rewriting_neverMatchesADestinationAgain() {
        // Given: `a` is overridden to `b`, and `b` to `c`.
        let overrides = overrides(
            (endpoint("https", "a.example.test"), endpoint("https", "b.example.test")),
            (endpoint("https", "b.example.test"), endpoint("https", "c.example.test"))
        )

        // When / Then
        #expect(overrides.rewriting("https://a.example.test/x") == "https://b.example.test/x")
    }

    // MARK: - rewritingRedirect

    private func request(
        _ url: String,
        headers: [(String, String)] = []
    ) -> Internals.RedirectRequest {
        .init(url: url, method: "GET", headers: .init(headers), hasBody: false)
    }

    @Test
    func rewritingRedirect_whenTheHopIsBackOnTheOriginThePreviousOneWentTo_putsTheCredentialsBack() {
        // Given: an executor compared the `Location` with the previous hop before the rewrite, saw
        // another origin and took the credentials off.
        let overrides = overrides(
            (endpoint("https", "staging.example.test"), endpoint("http", "127.0.0.1", port: 8080))
        )

        let previous = request(
            "http://127.0.0.1:8080/a",
            headers: [("Cookie", "session=abc"), ("Authorization", "Bearer secret"), ("X-Custom", "kept")]
        )
        var candidate = request("https://staging.example.test/b", headers: [("X-Custom", "kept")])

        // When
        overrides.rewritingRedirect(&candidate, previous: previous)

        // Then
        #expect(candidate.url == "http://127.0.0.1:8080/b")
        #expect(candidate.headers.first(name: "Cookie") == "session=abc")
        #expect(candidate.headers.first(name: "Authorization") == "Bearer secret")
        #expect(candidate.headers.first(name: "X-Custom") == "kept")
    }

    @Test
    func rewritingRedirect_whenTheHopLeavesTheOriginThePreviousOneWentTo_keepsWhatTheExecutorTookOff() {
        // Given
        let overrides = overrides(
            (endpoint("https", "elsewhere.example.test"), endpoint("http", "127.0.0.1", port: 9090))
        )

        let previous = request("http://127.0.0.1:8080/a", headers: [("Cookie", "session=abc")])
        var candidate = request("https://elsewhere.example.test/b")

        // When
        overrides.rewritingRedirect(&candidate, previous: previous)

        // Then
        #expect(candidate.url == "http://127.0.0.1:9090/b")
        #expect(!candidate.headers.contains(name: "Cookie"))
    }

    @Test
    func rewritingRedirect_whenNoRuleCovers_leavesTheRequestAlone() {
        // Given
        let overrides = overrides((endpoint("https", "staging.example.test"), endpoint("https", "real.example.test")))

        let previous = request("https://real.example.test/a", headers: [("Cookie", "session=abc")])
        var candidate = request("https://other.example.test/b")

        // When
        overrides.rewritingRedirect(&candidate, previous: previous)

        // Then
        #expect(candidate.url == "https://other.example.test/b")
        #expect(!candidate.headers.contains(name: "Cookie"))
    }

    // MARK: - Equatable

    @Test
    func equality_distinguishesTheRules() {
        // Given
        let a = overrides((endpoint("https", "a.example.test"), endpoint("https", "b.example.test")))
        let b = overrides((endpoint("https", "a.example.test"), endpoint("https", "c.example.test")))

        // When / Then
        #expect(a == a)
        #expect(a != b)
        #expect(a != Internals.URLOverrides())
    }

    @Test
    func sessionConfiguration_withDifferentOverrides_isNotTheSameClient() {
        // Given
        var lhs = Internals.Session.Configuration()
        var rhs = Internals.Session.Configuration()

        // When
        lhs.urlOverrides = overrides((endpoint("https", "a.example.test"), endpoint("https", "b.example.test")))

        // Then
        #expect(lhs != rhs)

        rhs.urlOverrides = lhs.urlOverrides
        #expect(lhs == rhs)
    }
}
