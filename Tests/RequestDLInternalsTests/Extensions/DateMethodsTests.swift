//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

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
