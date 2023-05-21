/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension DataCache {

    /// A cache policy enumeration that specifies the type of caching for data.
    public enum Policy: UInt8, Codable {

        /// Specifies caching data in memory.
        case memory

        /// Specifies caching data on disk.
        case disk
    }
}
