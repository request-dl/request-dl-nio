/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension DataCache.Policy {

    /// A set of cache policies that control the behavior of data caching.
    public struct Set: Sendable, Hashable, OptionSet, Codable {

        // MARK: - Public static properties

        /// Specifies caching data in memory.
        public static let memory = DataCache.Policy.Set(.memory)

        /// Specifies caching data on disk.
        public static let disk = DataCache.Policy.Set(.disk)

        /// Specifies caching data both in memory and on disk.
        public static let all: DataCache.Policy.Set = [.disk, .memory]

        // MARK: - Public properties

        public let rawValue: UInt8

        // MARK: - Inits

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /**
         Initializes a cache policy set with the specified cache policy.
         
         - Parameter policy: The cache policy to initialize the set with.
         */
        public init(_ policy: DataCache.Policy) {
            self.init(rawValue: 1 << policy.rawValue)
        }
    }
}
