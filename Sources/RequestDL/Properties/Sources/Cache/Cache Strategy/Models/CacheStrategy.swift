/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A cache strategy enumeration that represents different strategies for handling cached data.
public enum CacheStrategy: Sendable, Hashable {

    /// Ignores cached data and always performs a fresh load from the source.
    case ignoreCachedData

    /// Reloads and revalidates cached data.
    case reloadAndValidateCachedData

    /// Returns cached data if available, otherwise performs a load from the source.
    case returnCachedDataElseLoad

    /// Uses only cached data and doesn't make any network requests.
    case useCachedDataOnly
}
