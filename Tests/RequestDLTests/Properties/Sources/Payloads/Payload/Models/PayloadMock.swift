//
// See LICENSE for this package's licensing information.
//

import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Date
#endif

struct PayloadMock: Codable, Hashable {

    // MARK: - Internal properties

    let foo: String
    let date: Date

    // MARK: - Inits

    init(foo: String, date: Date) {
        self.foo = foo
        self.date = Self.zeroNanoseconds(date)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.foo = try container.decode(String.self, forKey: .foo)

        let date = try container.decode(Date.self, forKey: .date)
        self.date = Self.zeroNanoseconds(date)
    }

    // MARK: - Private static methods

    /// Floored to the nearest whole second, not truncated: a fractional timestamp of `-0.5`
    /// belongs to the second before it, not to zero. Matches `Date.toISO8601String()`'s rounding,
    /// which is the encoding this mock round-trips through.
    private static func zeroNanoseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}
