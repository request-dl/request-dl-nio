//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

struct DateMethodsTests {

    // MARK: - GregorianCalendar

    @Test
    func civilFromDaysAndDaysFromCivilRoundTripAroundKnownDates() {
        let cases: [(days: Int64, year: Int64, month: Int64, day: Int64)] = [
            (0, 1970, 1, 1),
            (-1, 1969, 12, 31),
            (-719_162, 1, 1, 1),
            (11_016, 2000, 2, 29),
            (47_482, 2100, 1, 1),
        ]

        for testCase in cases {
            let civil = Internals.GregorianCalendar.civilFromDays(testCase.days)
            #expect(civil.year == testCase.year)
            #expect(civil.month == testCase.month)
            #expect(civil.day == testCase.day)

            let days = Internals.GregorianCalendar.daysFromCivil(
                year: testCase.year,
                month: testCase.month,
                day: testCase.day
            )
            #expect(days == testCase.days)
        }
    }

    @Test
    func floorDivideRoundsTowardNegativeInfinity() {
        #expect(Internals.GregorianCalendar.floorDivide(7, by: 2) == 3)
        #expect(Internals.GregorianCalendar.floorDivide(-7, by: 2) == -4)
        #expect(Internals.GregorianCalendar.floorDivide(-1, by: 86_400) == -1)
        #expect(Internals.GregorianCalendar.floorDivide(0, by: 86_400) == 0)
    }

    @Test
    func padLeftPadsWithZerosAndKeepsTheMinusSignInFront() {
        #expect(Internals.GregorianCalendar.pad(7, to: 2) == "07")
        #expect(Internals.GregorianCalendar.pad(42, to: 2) == "42")
        #expect(Internals.GregorianCalendar.pad(-7, to: 2) == "-07")
        #expect(Internals.GregorianCalendar.pad(1_970, to: 4) == "1970")
    }

    // MARK: - ISO8601

    @Test
    func toISO8601StringFormatsAPositiveTimestamp() {
        let date = Date(timeIntervalSince1970: 1_698_400_800)
        #expect(date.toISO8601String() == "2023-10-27T10:00:00Z")
    }

    @Test
    func toISO8601StringFloorsAFractionalTimestampBeforeTheEpoch() {
        let date = Date(timeIntervalSince1970: -0.5)
        #expect(date.toISO8601String() == "1969-12-31T23:59:59Z")
    }

    // MARK: - HTTP date parsing

    @Test
    func httpDateParsesTheIMFFixdateFormWithTheDayName() {
        let date = Date(httpDate: "Sun, 06 Nov 1994 08:49:37 GMT")
        #expect(date != nil)
        #expect(date?.toHTTPDateString() == "Sun, 06 Nov 1994 08:49:37 GMT")
    }

    @Test
    func httpDateParsesTheFormWithoutTheDayName() {
        let date = Date(httpDate: "06 Nov 1994 08:49:37 GMT")
        #expect(date != nil)
        #expect(date?.toHTTPDateString() == "Sun, 06 Nov 1994 08:49:37 GMT")
    }

    @Test
    func httpDateReturnsNilWhenTooFewFieldsArePresent() {
        #expect(Date(httpDate: "Nov 1994 08:49:37 GMT") == nil)
        #expect(Date(httpDate: "") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheDayIsNotAnInteger() {
        #expect(Date(httpDate: "Sun, XX Nov 1994 08:49:37 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheMonthNameIsUnrecognized() {
        #expect(Date(httpDate: "Sun, 06 Foo 1994 08:49:37 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheYearIsNotAnInteger() {
        #expect(Date(httpDate: "Sun, 06 Nov XXXX 08:49:37 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheTimeDoesNotHaveThreeComponents() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:49 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenAnyTimeComponentIsNotAnInteger() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 XX:49:37 GMT") == nil)
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:XX:37 GMT") == nil)
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:49:XX GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheDayIsOutOfRange() {
        #expect(Date(httpDate: "Sun, 00 Nov 1994 08:49:37 GMT") == nil)
        #expect(Date(httpDate: "Sun, 32 Nov 1994 08:49:37 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheHourIsOutOfRange() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 24:49:37 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheMinuteIsOutOfRange() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:60:37 GMT") == nil)
    }

    @Test
    func httpDateAcceptsALeapSecond() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:49:60 GMT") != nil)
    }

    @Test
    func httpDateReturnsNilWhenTheSecondIsOutOfRange() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:49:61 GMT") == nil)
    }

    @Test(
        arguments: [
            "Sun, 06 Nov 400000000000 08:49:37 GMT",
            "Sun, 06 Nov 9223372036854775807 08:49:37 GMT",
            "Sun, 06 Nov -9223372036854775808 08:49:37 GMT",
            "Sun, 06 Nov 10000 08:49:37 GMT",
            "Sun, 06 Nov 94 08:49:37 GMT",
            "Sun, 06 Nov +1994 08:49:37 GMT",
        ]
    )
    func httpDateReturnsNilWhenTheYearIsNotFourDigits(_ value: String) {
        #expect(Date(httpDate: value) == nil)
    }

    @Test
    func httpDateReturnsNilWhenATimeComponentIsNotTwoDigits() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 8:49:37 GMT") == nil)
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:4:37 GMT") == nil)
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:49:+7 GMT") == nil)
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08::37 GMT") == nil)
    }

    @Test
    func httpDateReturnsNilWhenThereAreMoreFieldsThanTheGrammarHas() {
        #expect(Date(httpDate: "Sun, 06 Nov 1994 08:49:37 GMT extra") == nil)
    }

    @Test
    func httpDateReturnsNilWhenTheDayDoesNotExistInTheMonth() {
        #expect(Date(httpDate: "Sun, 31 Feb 2026 00:00:00 GMT") == nil)
        #expect(Date(httpDate: "Sun, 30 Feb 2024 00:00:00 GMT") == nil)
        #expect(Date(httpDate: "Sun, 29 Feb 2025 00:00:00 GMT") == nil)
        #expect(Date(httpDate: "Sun, 31 Apr 2026 00:00:00 GMT") == nil)
    }

    @Test
    func httpDateAcceptsTheLastDayOfEveryMonthLength() {
        #expect(Date(httpDate: "Thu, 29 Feb 2024 00:00:00 GMT") != nil)
        #expect(Date(httpDate: "Sat, 29 Feb 2000 00:00:00 GMT") != nil)
        #expect(Date(httpDate: "Fri, 29 Feb 2100 00:00:00 GMT") == nil)
        #expect(Date(httpDate: "Thu, 30 Apr 2026 00:00:00 GMT") != nil)
        #expect(Date(httpDate: "Sun, 31 May 2026 00:00:00 GMT") != nil)
    }

    // MARK: - HTTP date: the other two formats of RFC 9110

    /// 1994-11-06T08:49:37Z
    private static let sixthOfNovember1994 = Date(timeIntervalSince1970: 784_111_777)

    /// A recipient MUST accept the two obsolete formats, RFC 850 and asctime, next to the
    /// IMF-fixdate one.
    @Test(arguments: [
        "Sunday, 06-Nov-1994 08:49:37 GMT",
        "Sun Nov  6 08:49:37 1994",
        "Sun Nov 06 08:49:37 1994",
    ])
    func httpDateParsesTheObsoleteFormats(_ value: String) {
        #expect(Date(httpDate: value) == Self.sixthOfNovember1994)
    }

    /// Read against a fixed now: against the clock, a test of "94" would start reading 2094 in 2044.
    @Test
    func httpDateParsesRFC850WithATwoDigitYear() {
        // 2026-11-15
        let now = Date(timeIntervalSince1970: 1_794_700_800)

        #expect(Date(httpDate: "Sunday, 06-Nov-94 08:49:37 GMT", relativeTo: now) == Self.sixthOfNovember1994)
    }

    @Test
    func httpDateAppliesANumericZoneWithoutADayName() {
        #expect(Date(httpDate: "06 Nov 1994 09:49:37 +0100") == Self.sixthOfNovember1994)
    }

    /// The two digit year of RFC 850 reads as the closest year with those digits that is not
    /// more than 50 years ahead of now.
    @Test(arguments: [
        ("Sunday, 06-Nov-26 08:49:37 GMT", "Fri, 06 Nov 2026 08:49:37 GMT"),
        ("Sunday, 06-Nov-75 08:49:37 GMT", "Wed, 06 Nov 2075 08:49:37 GMT"),
        ("Sunday, 06-Nov-76 08:49:37 GMT", "Fri, 06 Nov 2076 08:49:37 GMT"),
        ("Sunday, 06-Nov-77 08:49:37 GMT", "Sun, 06 Nov 1977 08:49:37 GMT"),
        ("Sunday, 06-Nov-94 08:49:37 GMT", "Sun, 06 Nov 1994 08:49:37 GMT"),
        ("Sunday, 06-Nov-00 08:49:37 GMT", "Mon, 06 Nov 2000 08:49:37 GMT"),
    ])
    func httpDateReadsATwoDigitYearAgainstNow(_ value: String, _ expected: String) {
        // 2026-11-15
        let now = Date(timeIntervalSince1970: 1_794_700_800)

        #expect(Date(httpDate: value, relativeTo: now) == Date(httpDate: expected))
    }

    @Test(arguments: [
        "Sunday, 06-Foo-94 08:49:37 GMT",
        "Sunday, 6-Nov-94 08:49:37 GMT",
        "Sunday, 06-Nov-9 08:49:37 GMT",
        "Sunday, 06-Nov-994 08:49:37 GMT",
        "Sunday, 31-Apr-94 08:49:37 GMT",
        "Sunday, 06-Nov-94 08:49:37 PST",
        "Sunday, 06-Nov-94 08:49:37",
        "Foo, 06-Nov-94 08:49:37 GMT",
        "Sun Nov  6 08:49:37 94",
        "Sun Nov  6 08:49:37 1994 GMT",
        "Sun Nov 32 08:49:37 1994",
        "Sun Foo  6 08:49:37 1994",
        "Foo Nov  6 08:49:37 1994",
    ])
    func httpDateRejectsAMalformedObsoleteFormat(_ value: String) {
        #expect(Date(httpDate: value) == nil)
    }

    /// The zone was never looked at: `PST`, `+0100` and `garbage` all read as GMT, so a date in
    /// another zone came out hours away from what the server meant.
    @Test(arguments: [
        "Sun, 06 Nov 1994 08:49:37 PST",
        "Sun, 06 Nov 1994 08:49:37 EST",
        "Sun, 06 Nov 1994 08:49:37 CET",
        "Sun, 06 Nov 1994 08:49:37 garbage",
        "Sun, 06 Nov 1994 08:49:37 GMT+1",
        "Sun, 06 Nov 1994 08:49:37 +01",
        "Sun, 06 Nov 1994 08:49:37 +0160",
        "Sun, 06 Nov 1994 08:49:37 +2400",
        "Sun, 06 Nov 1994 08:49:37 0100",
        "Sun, 06 Nov 1994 08:49:37 Z",
    ])
    func httpDateRejectsAZoneItCannotRead(_ value: String) {
        #expect(Date(httpDate: value) == nil)
    }

    @Test(arguments: [
        ("Sun, 06 Nov 1994 08:49:37 GMT", 0.0),
        ("Sun, 06 Nov 1994 08:49:37 UTC", 0),
        ("Sun, 06 Nov 1994 08:49:37 gmt", 0),
        ("Sun, 06 Nov 1994 08:49:37 +0000", 0),
        ("Sun, 06 Nov 1994 08:49:37 -0000", 0),
        ("Sun, 06 Nov 1994 09:49:37 +0100", 0),
        ("Sun, 06 Nov 1994 03:49:37 -0500", 0),
        ("Sun, 06 Nov 1994 14:19:37 +0530", 0),
        ("Sun, 06 Nov 1994 08:49:37 +0100", -3_600),
    ])
    func httpDateAppliesANumericOrUTCZone(_ value: String, _ shift: Double) {
        #expect(Date(httpDate: value) == Date(timeIntervalSince1970: 784_111_777 + shift))
    }

    // MARK: - HTTP date formatting

    @Test
    func toHTTPDateStringFormatsAKnownDate() {
        let date = Date(timeIntervalSince1970: 784_111_777)
        #expect(date.toHTTPDateString() == "Sun, 06 Nov 1994 08:49:37 GMT")
    }

    @Test
    func toHTTPDateStringFloorsAFractionalTimestampBeforeTheEpoch() {
        let date = Date(timeIntervalSince1970: -0.5)
        #expect(date.toHTTPDateString() == "Wed, 31 Dec 1969 23:59:59 GMT")
    }
}
