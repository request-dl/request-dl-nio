//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// Where a URL has its user name and password, and what an error is allowed to say about them.
struct URLUserInfoTests {

    @Test(arguments: [
        "https://user:password@example.com",
        "https://user@example.com",
        "https://:password@example.com/path",
        "https://user:password@example.com:8443/path?q=1",
        "  https://user:password@example.com  ",
        "https://user:p%40ss@example.com",
    ])
    func isPresent_whenTheAuthorityHasUserInfo_isTrue(_ url: String) {
        #expect(URLUserInfo.isPresent(in: url))
    }

    @Test(arguments: [
        "https://example.com",
        "https://example.com:8443/a",
        "https://example.com/users/a@b.c",
        "https://example.com?email=a@b.c",
        "https://example.com#a@b",
        "/users/a@b.c",
        "a@b",
        "/search?redirect=http://user:password@example.com",
        "",
    ])
    func isPresent_whenTheAtSignIsNotInTheAuthority_isFalse(_ url: String) {
        #expect(!URLUserInfo.isPresent(in: url))
    }

    @Test(arguments: [
        "user:password@example.com",
        "user@example.com:8443",
        "user:password@example.com/path",
    ])
    func isPresentInHost_whenTheHostHasUserInfo_isTrue(_ host: String) {
        #expect(URLUserInfo.isPresent(inHost: host))
    }

    @Test(arguments: [
        "example.com",
        "example.com:8443",
        "example.com/users/a@b.c",
        "[::1]:8080",
    ])
    func isPresentInHost_whenTheHostHasNone_isFalse(_ host: String) {
        #expect(!URLUserInfo.isPresent(inHost: host))
    }

    @Test(arguments: [
        ("https://user:password@example.com/a?q=1", "https://REDACTED@example.com/a?q=1"),
        ("https://user@example.com", "https://REDACTED@example.com"),
        ("https://user:p@ss@example.com:8443", "https://REDACTED@example.com:8443"),
        ("https://example.com/a@b", "https://example.com/a@b"),
        ("/users/a@b", "/users/a@b"),
    ])
    func redactingURL_replacesTheUserInfoAndNothingElse(_ url: String, _ expected: String) {
        #expect(URLUserInfo.redacting(url: url) == expected)
    }

    @Test(arguments: [
        ("user:password@example.com", "REDACTED@example.com"),
        ("user:password@example.com/path", "REDACTED@example.com/path"),
        ("https://user:password@example.com", "https://REDACTED@example.com"),
        ("example.com", "example.com"),
        ("example.com/a@b", "example.com/a@b"),
    ])
    func redactingHost_replacesTheUserInfoAndNothingElse(_ host: String, _ expected: String) {
        #expect(URLUserInfo.redacting(host: host) == expected)
    }
}
