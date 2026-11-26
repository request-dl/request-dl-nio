//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

struct InternalsCookieParsingTests {

    @Test(arguments: [
        ("Wed, 09 Jun 2021 10:18:14 GMT", 1_623_233_894.0),
        ("Wednesday, 09-Jun-21 10:18:14 GMT", 1_623_233_894.0),
        ("Wed Jun  9 10:18:14 2021", 1_623_233_894.0),
        ("Thu, 01 Jan 1970 00:00:00 GMT", 0.0),
        ("Sun, 06 Nov 94 08:49:37 GMT", 784_111_777.0),
        ("Fri, 31-Dec-2038 23:59:59 GMT", 2_177_452_799.0),
    ])
    func parseDate_acceptsTheFormatsServersSend(string: String, expected: Double) {
        #expect(Internals.Cookie.parseDate(string)?.timeIntervalSince1970 == expected)
    }

    @Test(arguments: [
        "",
        "not a date",
        "Wed, 32 Jun 2021 10:18:14 GMT",
        "Wed, 09 Jun 2021 25:18:14 GMT",
        "Wed, 09 Jun 1600 10:18:14 GMT",
        "Wed, 09 Foo 2021 10:18:14 GMT",
    ])
    func parseDate_whenInvalid_returnsNil(string: String) {
        #expect(Internals.Cookie.parseDate(string) == nil)
    }

    @Test
    func splitter_whenValueIsASingleCookieWithAnExpiresComma_doesNotSplit() {
        let value = "a=1; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Path=/"
        #expect(Internals.SetCookieSplitter.split(value) == [value])
    }

    @Test
    func splitter_whenValueFoldsSeveralCookies_splitsAtTheRightCommas() {
        let value = "a=1; Expires=Wed, 09 Jun 2021 10:18:14 GMT, b=2, c=3; HttpOnly"
        #expect(
            Internals.SetCookieSplitter.split(value) == [
                "a=1; Expires=Wed, 09 Jun 2021 10:18:14 GMT",
                "b=2",
                "c=3; HttpOnly",
            ]
        )
    }

    @Test
    func splitter_whenACommaHasNoSpaceAfterIt_doesNotSplit() {
        #expect(Internals.SetCookieSplitter.split("a=1,b=2") == ["a=1,b=2"])
        #expect(Internals.SetCookieSplitter.split("a=1; Path=/,b=2") == ["a=1; Path=/,b=2"])
    }

    @Test
    func splitter_whenTheTransportJoinsWithACommaAndASpace_splits() {
        #expect(Internals.SetCookieSplitter.split("a=1, b=2") == ["a=1", "b=2"])
        #expect(Internals.SetCookieSplitter.split("a=1,b=2, c=3") == ["a=1,b=2", "c=3"])
    }

    @Test
    func domainMatches_followsRFC6265() {
        #expect(Internals.Cookie.domainMatches(host: "example.com", domain: "example.com"))
        #expect(Internals.Cookie.domainMatches(host: "a.example.com", domain: "example.com"))
        #expect(!Internals.Cookie.domainMatches(host: "badexample.com", domain: "example.com"))
        #expect(!Internals.Cookie.domainMatches(host: "1.2.3.4", domain: "3.4"))
        #expect(!Internals.Cookie.domainMatches(host: "com", domain: "example.com"))
    }

    @Test
    func isIPAddress_recognisesLiterals() {
        #expect(Internals.Cookie.isIPAddress("127.0.0.1"))
        #expect(Internals.Cookie.isIPAddress("::1"))
        #expect(!Internals.Cookie.isIPAddress("example.com"))
        #expect(!Internals.Cookie.isIPAddress("1.2.3.4.example.com"))
    }

    @Test
    func store_whenPathHasAControlCharacter_usesTheDefaultPathAndSurvivesASnapshot() throws {
        // Given
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let storage = Internals.CookieStorage()

        // When: HTAB is allowed in a header value, so it reaches the parser.
        storage.store(
            setCookieValues: ["a=1; Path=/x\ty; Max-Age=1000"],
            for: URL(string: "https://example.com/dir/page")!,
            now: now
        )

        // Then: the `Path` is treated as absent, so the cookie gets the default path.
        let snapshot = storage.snapshot(now: now)
        #expect(snapshot.map(\.path) == ["/dir"])

        let restored = Internals.CookieStorage()
        // `restore` returns how many cookies it did not add.
        #expect(restored.restore(snapshot, now: now) == 0)
    }
}
