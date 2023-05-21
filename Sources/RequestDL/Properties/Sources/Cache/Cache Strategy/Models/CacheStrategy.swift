/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A cache strategy enumeration that represents different strategies for handling cached data.
 */
public enum CacheStrategy: Sendable, Hashable {
    /**
     Ignores stored data in the cache and always performs a fresh load from the source.
     */
    case ignoresStored

    /**
     Uses stored data from the cache only and does not perform any network requests.
     */
    case usesStoredOnly

    /**
     Returns stored data from the cache if available, otherwise performs a load from the source.
     */
    case returnStoredElseLoad
}

