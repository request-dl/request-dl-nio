/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Seed: Sendable, Hashable, CustomStringConvertible {

    // MARK: - Internal static properties

    static var zero: Seed {
        .init(.zero)
    }

    // MARK: - Internal properties

    var description: String {
        "Seed(\(rawValue))"
    }

    // MARK: - Private properties

    private let rawValue: Int

    // MARK: - Inits

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    // MARK: - Internal methods

    func next() -> Seed {
        .init(rawValue + 1)
    }
}
