/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum CacheStrategy: Sendable, Hashable {
    case ignoresStored
    case usesStoredOnly
    case returnStoredElseLoad
}
