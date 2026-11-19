//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin)
import Foundation
#endif

/// `removingPercentEscapes` stands in for Foundation's `removingPercentEncoding`, which
/// `FoundationEssentials` builds do not have. These cases pin the behavior it must keep.
struct StringPercentDecodingTests {

    @Test(arguments: [
        ("plain", "plain"),
        ("", ""),
        ("a%20b", "a b"),
        ("p%40ss%3Aw%2Frd", "p@ss:w/rd"),
        ("%C3%A9", "\u{E9}"),
        ("%e2%82%ac", "\u{20AC}"),
        ("caf\u{E9}", "caf\u{E9}"),
        ("100%25", "100%"),
        ("%2525", "%25"),
        ("%F0%9F%98%80", "\u{1F600}"),
        ("a+b", "a+b"),
    ])
    func decodes(_ text: String, _ expected: String) {
        #expect(text.removingPercentEscapes == expected)
    }

    @Test
    func decodesAnEscapedNULWithoutDroppingIt() {
        #expect("a%00b".removingPercentEscapes == "a\u{0}b")
    }

    @Test(arguments: [
        "%",
        "100%",
        "%2",
        "%G0",
        "%0G",
        "50%OFF",
        "%FF",
        "%C3",
        "%C3%28",
        "%E2%82",
        "%80",
        "a%",
    ])
    func rejectsInvalidInput(_ text: String) {
        #expect(text.removingPercentEscapes == nil)
    }

    @Test
    func worksOnSubstrings() {
        #expect("xx%41yy".dropFirst(2).dropLast(2).removingPercentEscapes == "A")
    }

    #if canImport(Darwin)
    @Test(arguments: [
        "plain", "", "a%20b", "p%40ss", "%C3%A9", "%", "100%", "%2", "%G0", "50%OFF", "%FF", "%C3", "%C3%28",
        "%00", "a%00b", "%F0%9F%98%80", "%2525", "%e2%82%ac", "caf\u{E9}", "%ED%A0%80", "%C0%AF",
    ])
    func agreesWithFoundation(_ text: String) {
        #expect(text.removingPercentEscapes == text.removingPercentEncoding)
    }
    #endif
}
