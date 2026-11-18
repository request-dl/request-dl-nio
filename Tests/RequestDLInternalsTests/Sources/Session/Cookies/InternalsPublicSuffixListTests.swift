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
}
