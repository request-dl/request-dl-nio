//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsPublicSuffixListTests {

    private let contents = """
        // ===BEGIN ICANN DOMAINS===
        com
        co.uk   // trailing comment
        *.ck
        !www.ck

        // ===BEGIN PRIVATE DOMAINS===
        blogspot.com
        """

    @Test
    func isPublicSuffix_matchesExactWildcardAndExceptionRules() throws {
        let list = try Internals.PublicSuffixList(contents)

        #expect(list.isPublicSuffix("com"))
        #expect(list.isPublicSuffix("co.uk"))
        #expect(list.isPublicSuffix("CO.UK"))
        #expect(list.isPublicSuffix("blogspot.com"))
        #expect(list.isPublicSuffix("anything.ck"))
        #expect(!list.isPublicSuffix("www.ck"))
        #expect(!list.isPublicSuffix("example.co.uk"))
        #expect(!list.isPublicSuffix("example.com"))
    }

    @Test
    func init_whenContentsHaveNoRules_throws() {
        #expect(throws: Internals.PublicSuffixList.ParseError.noRules) {
            try Internals.PublicSuffixList("// only comments\n\n")
        }
    }

    /// A list is written in Unicode and a host or a `Domain` may arrive in either spelling.
    @Test(arguments: ["рф", "xn--p1ai", "РФ"])
    func isPublicSuffix_whenTheListIsUnicode_matchesEverySpellingOfTheName(spelling: String) throws {
        let list = try Internals.PublicSuffixList("рф\n公司.cn\n")

        #expect(list.isPublicSuffix(spelling))
        #expect(list.isPublicSuffix("xn--55qx5d.cn"))
        #expect(!list.isPublicSuffix("пример.рф"))
    }

    @Test
    func init_whenContentsAreNotAList_throws() {
        #expect(throws: Internals.PublicSuffixList.ParseError.malformed) {
            try Internals.PublicSuffixList("<!DOCTYPE html><html><body>404 Not Found</body></html>")
        }

        #expect(throws: Internals.PublicSuffixList.ParseError.malformed) {
            try Internals.PublicSuffixList("com\nHTTP/1.1 503 Service Unavailable\n")
        }
    }
}
