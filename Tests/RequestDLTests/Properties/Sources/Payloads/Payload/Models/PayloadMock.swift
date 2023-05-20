/*
 See LICENSE for this package's licensing information.
*/

import XCTest

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

    private static func zeroNanoseconds(_ date: Date) -> Date {
        Calendar.current.date(
            bySetting: .nanosecond,
            value: .zero,
            of: date
        ) ?? date
    }
}
