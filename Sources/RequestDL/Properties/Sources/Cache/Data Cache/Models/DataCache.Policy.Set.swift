/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension DataCache.Policy {

    public struct Set: Sendable, Hashable, OptionSet, Codable {

        // MARK: - Public static properties

        public static let memory = DataCache.Policy.Set(.memory)

        public static let disk = DataCache.Policy.Set(.disk)

        public static let all: DataCache.Policy.Set = [.disk, .memory]

        // MARK: - Public properties

        public let rawValue: UInt8

        // MARK: - Inits

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public init(_ policy: DataCache.Policy) {
            self.init(rawValue: 1 << policy.rawValue)
        }
    }
}
