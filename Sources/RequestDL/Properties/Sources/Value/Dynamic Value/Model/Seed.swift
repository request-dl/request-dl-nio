/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Seed: Hashable, CustomStringConvertible {

    private let rawValue: Int

    var description: String {
        "Seed(\(rawValue))"
    }

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    static var zero: Seed {
        .init(.zero)
    }

    func next() -> Seed {
        .init(rawValue + 1)
    }
}
