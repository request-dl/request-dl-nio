//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Date
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
    enum GregorianCalendar {

        // MARK: - Internal static methods

        /// Converts a count of days since 1970-01-01 into a calendar date.
        ///
        /// Defined for negative inputs, which is what dates before the epoch are.
        static func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
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
        static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
            let shiftedYear = year - (month <= 2 ? 1 : 0)

            let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
            let yearOfEra = shiftedYear - era * 400

            let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear

            return era * 146_097 + dayOfEra - 719_468
        }

        /// Integer division that rounds toward negative infinity.
        ///
        /// Swift's `/` rounds toward zero, which splits `-1 / 86400` into day zero with a
        /// remainder of minus one second. A calendar needs the day before, with a positive
        /// remainder.
        static func floorDivide(_ dividend: Int64, by divisor: Int64) -> Int64 {
            let quotient = dividend / divisor
            let remainder = dividend % divisor

            return remainder != 0 && (remainder < 0) != (divisor < 0) ? quotient - 1 : quotient
        }

        /// Left pads with zeros, keeping a leading minus in front for a negative year.
        static func pad(_ value: Int64, to length: Int) -> String {
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
    /// - Note: The previous implementation was wrong for every date before 1970. Swift's `/`
    /// and `%` truncate toward zero, so a negative timestamp produced a negative
    /// seconds-of-day, and the year search only ever counted forward from 1970. One second
    /// before the epoch came out as `1970-01-01T00:00:-1Z`.
    func toISO8601String() -> String {
        // Floored, not truncated. A fractional timestamp of -0.5 is half a second *before* the
        // epoch, so it belongs to 1969-12-31T23:59:59Z, not to 1970.
        let timestamp = Int64(timeIntervalSince1970.rounded(.down))

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
    /// Accepts the preferred IMF-fixdate form of RFC 9110, `Sun, 06 Nov 1994 08:49:37 GMT`, and
    /// tolerates the day name being absent. The obsolete RFC 850 and asctime forms are not
    /// accepted; no server has emitted them in decades, and reading a two digit year wrong is
    /// worse than treating the header as missing.
    ///
    /// - Note: Replaces a `DateComponents` plus `Calendar.current` conversion. Beyond needing
    /// three types that are not in `FoundationEssentials`, `Calendar.current` is whatever
    /// calendar the user picked. On a device set to the Buddhist or Japanese calendar, feeding
    /// it year 2026 produced a date centuries away, so cache expiry silently stopped working
    /// for those users. An HTTP date is always proleptic Gregorian and always UTC.
    init?(httpDate: String) {
        // Whitespace and the comma after the day name are the only separators that matter.
        let fields =
            httpDate
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)

        // With the day name: Sun 06 Nov 1994 08:49:37 GMT. Without it, one fewer.
        let offset: Int

        switch fields.count {
        case 5:
            offset = 0
        case 6...:
            offset = 1
        default:
            return nil
        }

        guard
            let day = Int64(fields[offset]),
            let month = Self.httpMonths[fields[offset + 1]],
            let year = Int64(fields[offset + 2])
        else { return nil }

        let time = fields[offset + 3].split(separator: ":")

        guard
            time.count == 3,
            let hour = Int64(time[0]),
            let minute = Int64(time[1]),
            let second = Int64(time[2])
        else { return nil }

        // Range checked before the arithmetic. The algorithm below happily accepts month 47 and
        // rolls it forward into some other year, which turns a malformed header into a
        // plausible looking date rather than into a rejection.
        guard
            (1...12).contains(month),
            (1...31).contains(day),
            (0...23).contains(hour),
            (0...59).contains(minute),
            // 60 for a leap second, which RFC 9110 permits.
            (0...60).contains(second)
        else { return nil }

        let days = Internals.GregorianCalendar.daysFromCivil(year: year, month: month, day: day)
        let timestamp = days * 86_400 + hour * 3_600 + minute * 60 + second

        // `Double`, not `TimeInterval`: the typealias would need another Foundation import.
        self.init(timeIntervalSince1970: Double(timestamp))
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

    /// This date as an HTTP date, the IMF-fixdate form of RFC 9110: `Sun, 06 Nov 1994 08:49:37 GMT`.
    ///
    /// The inverse of `init(httpDate:)` above. Nothing in this package's production paths needs
    /// to format one — only to parse an incoming `Expires`/`Last-Modified` — but tests that
    /// fabricate cache response headers need to build one without `DateFormatter`, which is not
    /// part of `FoundationEssentials` any more than `Calendar` is.
    func toHTTPDateString() -> String {
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
