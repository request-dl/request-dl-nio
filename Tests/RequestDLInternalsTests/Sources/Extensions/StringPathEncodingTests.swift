//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

/// The form of a URL path that goes on the wire: an escape a component already carries stays, and
/// what a path may not contain is encoded.
struct StringPathEncodingTests {

    @Test(arguments: [
        ("users", "users"),
        ("a b", "a%20b"),
        ("caf\u{E9}", "caf%C3%A9"),
        ("\u{20AC}", "%E2%82%AC"),
        ("a%2Fb", "a%2Fb"),
        ("a%2fb", "a%2Fb"),
        ("100%25", "100%25"),
        ("100%", "100%25"),
        ("50%OFF", "50%25OFF"),
        ("%", "%25"),
        ("%2", "%252"),
        ("%C3%A9", "%C3%A9"),
        ("a#b", "a%23b"),
        ("a?b", "a%3Fb"),
        ("a\\b", "a%5Cb"),
        ("a/b", "a/b"),
        ("x:y@z", "x:y@z"),
        ("(a)*+,;=!$&'", "(a)*+,;=!$&'"),
        ("~._-", "~._-"),
    ])
    func addingPercentEncodingForURLPath(_ text: String, _ expected: String) {
        #expect(text.addingPercentEncodingForURLPath() == expected)
    }

    @Test(arguments: ["a b", "caf\u{E9}", "a%2Fb", "100%", "%C3%A9", "a#b"])
    func addingPercentEncodingForURLPath_isIdempotent(_ text: String) {
        let once = text.addingPercentEncodingForURLPath()

        #expect(once.addingPercentEncodingForURLPath() == once)
    }

    @Test
    func joinedAsPath_keepsAnEscapeAtTheEdgeOfAComponent() {
        // The old trimming dropped a `%` at the start of a component, turning `%C3%A9` into `C3%A9`.
        #expect(["%C3%A9", "%2Fa"].joinedAsPath() == "%C3%A9/%2Fa")
    }

    @Test
    func joinedAsPath_encodesWhatAPathMayNotContain() {
        #expect(["users", "a b", "caf\u{E9}", "100%"].joinedAsPath() == "users/a%20b/caf%C3%A9/100%25")
    }

    @Test
    func joinedAsPath_stillTrimsWhitespaceAndSlashesAndDropsEmptyComponents() {
        #expect([" a/ ", "/b/", "", " ", "c"].joinedAsPath() == "a/b/c")
    }

    @Test
    func joinedAsPath_keepsATrailingSlash() {
        #expect(["a", "b/"].joinedAsPath() == "a/b/")
    }
}
