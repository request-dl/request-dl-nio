//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

struct InternalsCookieDateTests {

    // Reference values computed with Python's `calendar.timegm`, not with the code
    // under test.
    @Test(arguments: [
        (9_999, 12, 31, 23, 59, 59, Int64(253_402_300_799)),
        (2_038, 1, 19, 3, 14, 8, Int64(2_147_483_648)),
        (2_038, 1, 19, 3, 14, 7, Int64(2_147_483_647)),
        (1_970, 1, 1, 0, 0, 0, Int64(0)),
        (1_901, 12, 13, 20, 45, 52, Int64(-2_147_483_648)),
        (1_901, 12, 13, 20, 45, 51, Int64(-2_147_483_649)),
        (1_601, 1, 1, 0, 0, 0, Int64(-11_644_473_600)),
    ])
    func secondsSinceEpoch_isExactOutsideThe32BitRange(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        expected: Int64
    ) {
        let seconds = Internals.Cookie.secondsSinceEpoch(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )

        #expect(seconds == expected)
    }

    @Test
    func secondsSinceEpoch_atTheYearsTheParserAcceptsAtTheEnds_doesNotFitAnInt32() {
        // Why the helper returns `Int64`: with a 32-bit `Int` (watchOS arm64_32) these overflow.
        let latest = Internals.Cookie.secondsSinceEpoch(
            year: 9_999,
            month: 12,
            day: 31,
            hour: 23,
            minute: 59,
            second: 59
        )

        let earliest = Internals.Cookie.secondsSinceEpoch(
            year: 1_601,
            month: 1,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0
        )

        #expect(latest > Int64(Int32.max))
        #expect(earliest < Int64(Int32.min))
    }

    @Test
    func parseDate_whenYearIs9999_returnsTheExactInstant() {
        let date = Internals.Cookie.parseDate("Fri, 31 Dec 9999 23:59:59 GMT")
        #expect(date?.timeIntervalSince1970 == 253_402_300_799)
    }

    @Test
    func parseDate_whenYearIs1601_returnsTheExactInstant() {
        let date = Internals.Cookie.parseDate("Mon, 01 Jan 1601 00:00:00 GMT")
        #expect(date?.timeIntervalSince1970 == -11_644_473_600)
    }

    @Test
    func parseDate_justAfter2038_returnsTheExactInstant() {
        let date = Internals.Cookie.parseDate("Tue, 19 Jan 2038 03:14:08 GMT")
        #expect(date?.timeIntervalSince1970 == 2_147_483_648)
    }

    @Test
    func parse_whenExpiresIs9999_keepsTheCookieAsAFarFutureOne() throws {
        let origin = Internals.Cookie.Origin(host: "example.com", path: "/", isSecure: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let cookie = try #require(
            Internals.Cookie.parse(
                "id=1; Expires=Fri, 31 Dec 9999 23:59:59 GMT",
                from: origin,
                now: now,
                publicSuffixList: nil
            )
        )

        #expect(cookie.expires?.timeIntervalSince1970 == 253_402_300_799)
        #expect(!cookie.isExpired(at: now))
    }

    @Test
    func parse_whenExpiresIs1601_isADeletion() throws {
        let origin = Internals.Cookie.Origin(host: "example.com", path: "/", isSecure: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let cookie = try #require(
            Internals.Cookie.parse(
                "id=1; Expires=Mon, 01 Jan 1601 00:00:00 GMT",
                from: origin,
                now: now,
                publicSuffixList: nil
            )
        )

        #expect(cookie.expires?.timeIntervalSince1970 == -11_644_473_600)
        #expect(cookie.isExpired(at: now))
    }
}
