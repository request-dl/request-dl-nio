//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsRedirectSanitizerTests {

    @Test
    func sanitize_whenOriginChanges_removesEverythingThatBelongsToTheOldOne() {
        // Given
        var headers: Internals.HTTPHeaders = [
            "Authorization": "Bearer secret",
            "cookie": "session=abc",
            "Origin": "https://example.com",
            "Proxy-Authorization": "Basic secret",
            "HOST": "api.internal",
            "X-Custom": "kept",
        ]

        // When
        Internals.RedirectSanitizer.sanitize(
            &headers,
            from: "https://example.com/a",
            to: "https://other.example.com/b"
        )

        // Then
        #expect(headers.pairs.map(\.name) == ["X-Custom"])
    }

    @Test(
        arguments: [
            ("https://example.com/a", "https://example.com/b"),
            ("https://example.com:8443/a", "https://example.com:8443/b?q=1"),
            ("http://example.com/a", "http://example.com/a#fragment"),
        ]
    )
    func sanitize_whenOriginIsTheSame_keepsEverything(previous: String, next: String) {
        // Given
        var headers: Internals.HTTPHeaders = ["Authorization": "Bearer secret", "Host": "api.internal"]

        // When
        Internals.RedirectSanitizer.sanitize(&headers, from: previous, to: next)

        // Then
        #expect(headers.pairs.count == 2)
    }

    /// Scheme, host and port are each part of the origin (RFC 6454).
    @Test(
        arguments: [
            ("https://example.com/a", "http://example.com/a"),
            ("https://example.com/a", "https://example.org/a"),
            ("https://example.com/a", "https://example.com:8443/a"),
            ("https://example.com:8443/a", "https://example.com:9443/a"),
        ]
    )
    func isSameOrigin_whenSchemeHostOrPortDiffers_isFalse(previous: String, next: String) {
        #expect(!Internals.RedirectSanitizer.isSameOrigin(previous, next))
    }

    /// Nothing to compare means nothing to trust: it is treated as another origin.
    @Test
    func isSameOrigin_whenAURLDoesNotParse_isFalse() {
        #expect(!Internals.RedirectSanitizer.isSameOrigin("https://example.com/a", ""))
    }

    // MARK: - Hidden headers

    @Test
    func sanitize_whenOriginChangesAndHeadersAreHidden_removesBothScopesAndKeepsTheRest() {
        // Given
        var headers: Internals.HTTPHeaders = ["X-Api-Key": "a", "X-Token": "b", "X-Custom": "kept"]

        var hidden = Internals.RedirectHiddenHeaders()
        hidden.insert(name: "x-api-key", onAnyRedirect: false)
        hidden.insert(name: "X-TOKEN", onAnyRedirect: true)

        // When
        Internals.RedirectSanitizer.sanitize(
            &headers,
            from: "https://example.com/a",
            to: "https://other.example.com/b",
            hidden: hidden
        )

        // Then
        #expect(headers.pairs.map(\.name) == ["X-Custom"])
    }

    @Test
    func sanitize_whenOriginIsTheSameAndHeadersAreHidden_removesOnlyWhatIsHiddenOnAnyRedirect() {
        // Given
        var headers: Internals.HTTPHeaders = [
            "X-Api-Key": "a",
            "X-Token": "b",
            "Authorization": "Bearer secret",
        ]

        var hidden = Internals.RedirectHiddenHeaders()
        hidden.insert(name: "X-Api-Key", onAnyRedirect: false)
        hidden.insert(name: "x-token", onAnyRedirect: true)

        // When
        Internals.RedirectSanitizer.sanitize(
            &headers,
            from: "https://example.com/a",
            to: "https://example.com/b",
            hidden: hidden
        )

        // Then
        #expect(Set(headers.pairs.map(\.name)) == ["X-Api-Key", "Authorization"])
    }

    @Test
    func insert_whenANameIsMarkedForBothScopes_keepsItInEach() {
        // Given
        var hidden = Internals.RedirectHiddenHeaders()

        // When
        hidden.insert(name: "X-Api-Key", onAnyRedirect: false)
        hidden.insert(name: "x-api-KEY", onAnyRedirect: true)
        hidden.insert(name: "", onAnyRedirect: true)

        // Then
        #expect(hidden.otherOrigins == ["x-api-key"])
        #expect(hidden.anyRedirect == ["x-api-key"])
        #expect(!hidden.isEmpty)
        #expect(Internals.RedirectHiddenHeaders().isEmpty)
    }

    @Test
    func configuration_whenHiddenHeadersDiffer_isNotEqual() {
        // Given
        var lhs = Internals.Session.Configuration()
        let rhs = Internals.Session.Configuration()

        // When
        lhs.redirectHiddenHeaders.insert(name: "X-Api-Key", onAnyRedirect: false)

        // Then
        #expect(lhs != rhs)
    }

    // MARK: - Reported URL

    @Test(
        arguments: [
            ("http://user:pw@example.com/next", "http://example.com/next"),
            ("https://user@example.com:8443/a?q=a@b#frag", "https://example.com:8443/a?q=a@b#frag"),
            ("http://:pw@example.com/", "http://example.com/"),
            ("http://example.com/a?mail=a@b", "http://example.com/a?mail=a@b"),
            ("http://example.com/", "http://example.com/"),
            ("http://[bad", "http://[bad"),
            ("", ""),
        ]
    )
    func removingUserInfo_takesTheUserAndPasswordOutOfTheReportedURL(url: String, expected: String) {
        #expect(Internals.RedirectSanitizer.removingUserInfo(from: url) == expected)
    }

    @Test(
        arguments: [
            (UInt(304), true), (305, true), (301, false), (302, false), (303, false), (307, false), (200, false),
        ]
    )
    func isNotARedirect_isTrueForNotModifiedAndUseProxyOnly(statusCode: UInt, expected: Bool) {
        #expect(Internals.RedirectSanitizer.isNotARedirect(statusCode: statusCode) == expected)
    }
}
