//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.Cookie {

    /// RFC 6265 section 5.1.1: the lenient, delimiter-based date parser every `Expires` goes
    /// through, which accepts the three formats servers send (RFC 1123, RFC 850 and `asctime`)
    /// and the many malformed variants of them seen in the wild.
    static func parseDate(_ string: String) -> Date? {
        var time: (hour: Int, minute: Int, second: Int)?
        var dayOfMonth: Int?
        var month: Int?
        var year: Int?

        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

        for token in string.unicodeScalars.split(whereSeparator: isDelimiter).map(String.init) {
            if time == nil, let parsed = parseTime(token) {
                time = parsed
            } else if dayOfMonth == nil, let parsed = leadingNumber(token, maximumDigits: 2) {
                dayOfMonth = parsed
            } else if month == nil, token.count >= 3, let index = months.firstIndex(of: token.prefix(3).lowercased()) {
                month = index + 1
            } else if year == nil, let parsed = leadingNumber(token, maximumDigits: 4),
                token.prefix(while: \.isNumber).count >= 2
            {
                year = parsed
            }
        }

        guard var year, let time, let dayOfMonth, let month else {
            return nil
        }

        if (70...99).contains(year) {
            year += 1_900
        } else if (0...69).contains(year) {
            year += 2_000
        }

        guard
            (1...31).contains(dayOfMonth),
            year >= 1_601,
            time.hour <= 23, time.minute <= 59, time.second <= 59
        else {
            return nil
        }

        let seconds = secondsSinceEpoch(
            year: year,
            month: month,
            day: dayOfMonth,
            hour: time.hour,
            minute: time.minute,
            second: time.second
        )

        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Seconds since 1970-01-01T00:00:00Z of a proleptic Gregorian date and time.
    ///
    /// Computed in `Int64` on purpose. `Int` is 32 bits on watchOS `arm64_32`, where `days * 86_400`
    /// no longer fits for any date after 2038-01-19 or before 1901-12-13, and the parser accepts
    /// every year from 1601 to 9999: a trap, from one `Expires` a server sent.
    static func secondsSinceEpoch(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> Int64 {
        let days = Internals.GregorianCalendar.daysFromCivil(year: Int64(year), month: Int64(month), day: Int64(day))
        return days * 86_400 + Int64(hour) * 3_600 + Int64(minute) * 60 + Int64(second)
    }

    // MARK: - Private static methods

    private static func isDelimiter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x20...0x2F, 0x3B...0x40, 0x5B...0x60, 0x7B...0x7E:
            return true
        default:
            return false
        }
    }

    /// `1*2DIGIT ":" 1*2DIGIT ":" 1*2DIGIT`, optionally followed by anything that is not a digit.
    private static func parseTime(_ token: String) -> (hour: Int, minute: Int, second: Int)? {
        let fields = token.split(separator: ":", omittingEmptySubsequences: false)

        guard fields.count == 3,
            let hour = leadingNumber(String(fields[0]), maximumDigits: 2, exact: true),
            let minute = leadingNumber(String(fields[1]), maximumDigits: 2, exact: true),
            let second = leadingNumber(String(fields[2]), maximumDigits: 2)
        else {
            return nil
        }

        return (hour, minute, second)
    }

    /// The `1*maximumDigits DIGIT` a token starts with, as long as a non-digit (or nothing)
    /// follows. `exact` requires that nothing follows at all.
    private static func leadingNumber(_ token: String, maximumDigits: Int, exact: Bool = false) -> Int? {
        let digits = token.prefix { $0.isASCII && $0.isNumber }

        guard !digits.isEmpty, digits.count <= maximumDigits else {
            return nil
        }

        guard !exact || digits.count == token.count else {
            return nil
        }

        return Int(digits)
    }
}
