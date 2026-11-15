//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

extension Internals {

    /// Proleptic Gregorian calendar arithmetic, in both directions.
    ///
    /// Exists because `Calendar`, `TimeZone` and `DateComponents` are not part of
    /// `FoundationEssentials`, and neither is `ISO8601DateFormatter` or `DateFormatter`. Every
    /// date this package handles is a fixed offset UTC timestamp on the wire, so none of the
    /// locale and time zone machinery those types carry is needed.
    ///
    /// - Important: The constants below come from a published algorithm and are not tunable.
    /// They fall out of shifting the year to start in March, which puts the leap day at the end
    /// and makes the month lengths regular. See
    /// https://howardhinnant.github.io/date_algorithms.html for the derivation. Both directions
    /// are validated against a reference implementation, including the century rule at 1900 and
    /// 2100 and the 400 year rule at 2000.
    package enum GregorianCalendar {

        // MARK: - Internal static methods

        /// Converts a count of days since 1970-01-01 into a calendar date.
        ///
        /// Defined for negative inputs, which is what dates before the epoch are.
        package static func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
            // Shift the epoch to 0000-03-01, the start of a 400 year cycle.
            let shifted = days + 719_468

            let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
            let dayOfEra = shifted - era * 146_097
            let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365

            let year = yearOfEra + era * 400
            let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)

            // March is month zero in the shifted year.
            let shiftedMonth = (5 * dayOfYear + 2) / 153

            let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
            let month = shiftedMonth + (shiftedMonth < 10 ? 3 : -9)

            // January and February belong to the following calendar year.
            return (year + (month <= 2 ? 1 : 0), month, day)
        }

        /// Converts a calendar date into a count of days since 1970-01-01.
        ///
        /// The exact inverse of ``civilFromDays(_:)``.
        package static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
            let shiftedYear = year - (month <= 2 ? 1 : 0)

            let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
            let yearOfEra = shiftedYear - era * 400

            let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear

            return era * 146_097 + dayOfEra - 719_468
        }

        /// The number of days in `month` of `year`, leap years included.
        package static func daysInMonth(year: Int64, month: Int64) -> Int64 {
            switch month {
            case 2:
                let isLeapYear = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
                return isLeapYear ? 29 : 28
            case 4, 6, 9, 11:
                return 30
            default:
                return 31
            }
        }

        /// Integer division that rounds toward negative infinity.
        ///
        /// Swift's `/` rounds toward zero, which splits `-1 / 86400` into day zero with a
        /// remainder of minus one second. A calendar needs the day before, with a positive
        /// remainder.
        package static func floorDivide(_ dividend: Int64, by divisor: Int64) -> Int64 {
            let quotient = dividend / divisor
            let remainder = dividend % divisor

            return remainder != 0 && (remainder < 0) != (divisor < 0) ? quotient - 1 : quotient
        }

        /// Left pads with zeros, keeping a leading minus in front for a negative year.
        package static func pad(_ value: Int64, to length: Int) -> String {
            let isNegative = value < 0
            var digits = String(value.magnitude)

            while digits.count < length {
                digits = "0" + digits
            }

            return isNegative ? "-" + digits : digits
        }
    }
}

// MARK: - ISO8601

extension Date {

    /// This date as a strict ISO8601 UTC string, for example `2023-10-27T10:00:00Z`.
    ///
    /// Matches `ISO8601DateFormatter` with `.withInternetDateTime`: no fractional seconds,
    /// always `Z`.
    ///
    /// - Returns: `nil` when the date is NaN, infinite or so far from 1970 that its seconds do
    /// not fit in an `Int64`. `Int64(_:)` traps on those, and a date read from a server and sent
    /// back as a cursor must not be able to take the process down.
    ///
    /// - Note: The previous implementation was wrong for every date before 1970. Swift's `/`
    /// and `%` truncate toward zero, so a negative timestamp produced a negative
    /// seconds-of-day, and the year search only ever counted forward from 1970. One second
    /// before the epoch came out as `1970-01-01T00:00:-1Z`.
    package func toISO8601String() -> String? {
        // Floored, not truncated. A fractional timestamp of -0.5 is half a second *before* the
        // epoch, so it belongs to 1969-12-31T23:59:59Z, not to 1970.
        guard let timestamp = Int64(exactly: timeIntervalSince1970.rounded(.down)) else {
            return nil
        }

        let days = Internals.GregorianCalendar.floorDivide(timestamp, by: 86_400)
        let secondsOfDay = timestamp - days * 86_400

        let date = Internals.GregorianCalendar.civilFromDays(days)

        let pad = Internals.GregorianCalendar.pad

        return pad(date.year, 4)
            + "-" + pad(date.month, 2)
            + "-" + pad(date.day, 2)
            + "T" + pad(secondsOfDay / 3_600, 2)
            + ":" + pad((secondsOfDay % 3_600) / 60, 2)
            + ":" + pad(secondsOfDay % 60, 2)
            + "Z"
    }
}

// MARK: - HTTP date

extension Date {

    /// Parses an HTTP date, as `Expires`, `Last-Modified` and `Date` carry it.
    ///
    /// Accepts the three formats of RFC 9110 §5.6.7:
    ///
    /// - IMF-fixdate, the preferred one: `Sun, 06 Nov 1994 08:49:37 GMT`. The day name is
    ///   tolerated being absent, and is not checked against the date.
    /// - RFC 850, obsolete: `Sunday, 06-Nov-94 08:49:37 GMT`. A two digit year reads as the
    ///   closest year with those digits that is not more than 50 years ahead of now, as the RFC
    ///   says; a four digit one is taken as it is.
    /// - asctime, obsolete: `Sun Nov  6 08:49:37 1994`. It has no zone, and is GMT.
    ///
    /// The zone is read, not assumed: `GMT` and `UTC`, or a numeric offset (`+0100`) that shifts
    /// the instant. Anything else (`PST`, `garbage`) makes the whole value `nil`, since an
    /// abbreviation like `PST` names more than one offset and guessing GMT put the date hours
    /// away from what the server meant.
    ///
    /// - Note: Replaces a `DateComponents` plus `Calendar.current` conversion. Beyond needing
    /// three types that are not in `FoundationEssentials`, `Calendar.current` is whatever
    /// calendar the user picked. On a device set to the Buddhist or Japanese calendar, feeding
    /// it year 2026 produced a date centuries away, so cache expiry silently stopped working
    /// for those users. An HTTP date is always proleptic Gregorian and always UTC.
    package init?(httpDate: String) {
        self.init(httpDate: httpDate, relativeTo: Date())
    }

    /// - Parameter now: What a two digit year of the RFC 850 format is read against.
    package init?(httpDate: String, relativeTo now: Date) {
        // Whitespace and the comma after the day name are the only separators that matter.
        let fields =
            httpDate
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)

        guard let first = fields.first?.utf8.first else {
            return nil
        }

        let parsed: (date: DateFields, zone: Int64)?

        if first >= 0x30 && first <= 0x39 {
            // No day name: `06 Nov 1994 08:49:37 GMT`.
            parsed = Self.imfFixdate(fields[...])
        } else if fields.count > 1, fields[1].contains("-") {
            // `Sunday, 06-Nov-94 08:49:37 GMT`. The day name has to be one.
            parsed = Self.isWeekday(fields[0]) ? Self.rfc850(fields, relativeTo: now) : nil
        } else if fields.count > 1, Self.httpMonths[fields[1]] != nil {
            // `Sun Nov  6 08:49:37 1994`.
            parsed = Self.isWeekday(fields[0]) ? Self.asctime(fields) : nil
        } else {
            // `Sun, 06 Nov 1994 08:49:37 GMT`. Whatever the day name is, it is not checked.
            parsed = Self.imfFixdate(fields.dropFirst())
        }

        guard let parsed else {
            return nil
        }

        let date = parsed.date

        // Range checked before the arithmetic. The algorithm below happily accepts month 47 and
        // rolls it forward into some other year, which turns a malformed header into a
        // plausible looking date rather than into a rejection.
        guard
            (1...12).contains(date.month),
            (1...Internals.GregorianCalendar.daysInMonth(year: date.year, month: date.month))
                .contains(date.day),
            (0...23).contains(date.hour),
            (0...59).contains(date.minute),
            // 60 for a leap second, which RFC 9110 permits.
            (0...60).contains(date.second)
        else { return nil }

        let days = Internals.GregorianCalendar.daysFromCivil(
            year: date.year,
            month: date.month,
            day: date.day
        )
        let timestamp = days * 86_400 + date.hour * 3_600 + date.minute * 60 + date.second - parsed.zone

        // `Double`, not `TimeInterval`: the typealias would need another Foundation import.
        self.init(timeIntervalSince1970: Double(timestamp))
    }

    // MARK: - HTTP date: the three formats

    private struct DateFields {
        let year: Int64
        let month: Int64
        let day: Int64
        let hour: Int64
        let minute: Int64
        let second: Int64
    }

    // ASCII digits only, in the lengths the grammar gives. `Int64(_:)` alone takes a sign and
    // any number of digits, and an unbounded year overflows the arithmetic below.
    private static func number(_ field: some StringProtocol, digits: ClosedRange<Int>) -> Int64? {
        guard digits.contains(field.utf8.count), field.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
            return nil
        }

        return Int64(field)
    }

    private static func time(_ field: String) -> (hour: Int64, minute: Int64, second: Int64)? {
        let time = field.split(separator: ":", omittingEmptySubsequences: false)

        guard
            time.count == 3,
            let hour = number(time[0], digits: 2...2),
            let minute = number(time[1], digits: 2...2),
            let second = number(time[2], digits: 2...2)
        else { return nil }

        return (hour, minute, second)
    }

    /// `GMT`, `UTC` or `+hhmm`/`-hhmm`, as the number of seconds the zone is ahead of UTC.
    private static func zone(_ field: String) -> Int64? {
        switch field.uppercased() {
        case "GMT", "UTC":
            return 0
        default:
            break
        }

        guard
            field.utf8.count == 5,
            let sign = field.utf8.first,
            sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-"),
            let hours = number(field.dropFirst().prefix(2), digits: 2...2),
            let minutes = number(field.dropFirst(3), digits: 2...2),
            hours <= 23,
            minutes <= 59
        else { return nil }

        let offset = hours * 3_600 + minutes * 60

        return sign == UInt8(ascii: "-") ? -offset : offset
    }

    /// `[Sun,] 06 Nov 1994 08:49:37 GMT`, with the day name already removed.
    private static func imfFixdate(_ fields: ArraySlice<String>) -> (date: DateFields, zone: Int64)? {
        let fields = Array(fields)

        guard
            fields.count == 5,
            let day = number(fields[0], digits: 1...2),
            let month = httpMonths[fields[1]],
            let year = number(fields[2], digits: 4...4),
            let time = time(fields[3]),
            let zone = zone(fields[4])
        else { return nil }

        return (
            DateFields(year: year, month: month, day: day, hour: time.hour, minute: time.minute, second: time.second),
            zone
        )
    }

    /// `Sunday, 06-Nov-94 08:49:37 GMT`.
    private static func rfc850(_ fields: [String], relativeTo now: Date) -> (date: DateFields, zone: Int64)? {
        let date = fields[1].split(separator: "-", omittingEmptySubsequences: false)

        guard
            fields.count == 4,
            date.count == 3,
            let day = number(date[0], digits: 2...2),
            let month = httpMonths[String(date[1])],
            let year = number(date[2], digits: 2...4),
            date[2].count == 2 || date[2].count == 4,
            let time = time(fields[2]),
            let zone = zone(fields[3])
        else { return nil }

        return (
            DateFields(
                year: date[2].count == 4 ? year : fullYear(ofTwoDigit: year, relativeTo: now),
                month: month,
                day: day,
                hour: time.hour,
                minute: time.minute,
                second: time.second
            ),
            zone
        )
    }

    /// RFC 9110 §5.6.7: a two digit year that appears to be more than 50 years in the future is
    /// the most recent year in the past with the same last two digits. Compared by year.
    private static func fullYear(ofTwoDigit year: Int64, relativeTo now: Date) -> Int64 {
        guard let timestamp = Int64(exactly: now.timeIntervalSince1970.rounded(.down)) else {
            return 1900 + year
        }

        let currentYear = Internals.GregorianCalendar.civilFromDays(
            Internals.GregorianCalendar.floorDivide(timestamp, by: 86_400)
        ).year

        let candidate = currentYear - currentYear % 100 + year

        return candidate - currentYear > 50 ? candidate - 100 : candidate
    }

    /// `Sun Nov  6 08:49:37 1994`. No zone: asctime is GMT.
    private static func asctime(_ fields: [String]) -> (date: DateFields, zone: Int64)? {
        guard
            fields.count == 5,
            let month = httpMonths[fields[1]],
            let day = number(fields[2], digits: 1...2),
            let time = time(fields[3]),
            let year = number(fields[4], digits: 4...4)
        else { return nil }

        return (
            DateFields(year: year, month: month, day: day, hour: time.hour, minute: time.minute, second: time.second), 0
        )
    }

    private static func isWeekday(_ field: String) -> Bool {
        httpWeekdays.contains(field) || httpFullWeekdays.contains(field)
    }

    private static let httpMonths: [String: Int64] = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4,
        "May": 5, "Jun": 6, "Jul": 7, "Aug": 8,
        "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    ]

    private static let httpMonthNames = [
        1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun",
        7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec",
    ]

    private static let httpWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let httpFullWeekdays = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    /// This date as an HTTP date, the IMF-fixdate form of RFC 9110: `Sun, 06 Nov 1994 08:49:37 GMT`.
    ///
    /// The inverse of `init(httpDate:)` above. Production paths only parse an incoming
    /// `Expires`/`Last-Modified`, but tests that fabricate cache response headers need to build
    /// one without `DateFormatter`, which is not part of `FoundationEssentials` any more than
    /// `Calendar` is.
    package func toHTTPDateString() -> String {
        let timestamp = Int64(timeIntervalSince1970.rounded(.down))

        let days = Internals.GregorianCalendar.floorDivide(timestamp, by: 86_400)
        let secondsOfDay = timestamp - days * 86_400

        let date = Internals.GregorianCalendar.civilFromDays(days)
        let pad = Internals.GregorianCalendar.pad

        // 1970-01-01, day zero, was a Thursday. `% 7` can come back negative for a day before
        // the epoch, so the extra `+ 7` normalizes it before indexing.
        let weekday = Self.httpWeekdays[Int(((days % 7) + 7 + 4) % 7)]
        let month = Self.httpMonthNames[Int(date.month)] ?? ""

        return "\(weekday), " + pad(date.day, 2) + " \(month) " + pad(date.year, 4)
            + " " + pad(secondsOfDay / 3_600, 2)
            + ":" + pad((secondsOfDay % 3_600) / 60, 2)
            + ":" + pad(secondsOfDay % 60, 2)
            + " GMT"
    }
}
