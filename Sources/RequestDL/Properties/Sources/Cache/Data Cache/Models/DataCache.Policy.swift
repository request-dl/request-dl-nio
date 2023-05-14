/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension DataCache {

    public enum Policy: UInt8, Codable {
        case memory
        case disk
    }
}
