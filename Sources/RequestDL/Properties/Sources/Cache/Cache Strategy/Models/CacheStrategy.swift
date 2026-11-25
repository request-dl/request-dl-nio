//
// See LICENSE for this package's licensing information.
//

/// A cache strategy enumeration that represents different strategies for handling cached data.
///
/// A stored response is fresh for as long as the server said (`max-age`, or `Expires`), or, when it
/// said nothing, for a tenth of the time since the resource last changed (`Last-Modified` against
/// `Date`) and at most a day. One with neither is never fresh. An error response (`404`, `410`, ...)
/// is stored and reused only when it declares its own lifetime.
public enum CacheStrategy: Sendable, Hashable {

    /// Ignores cached data and always performs a fresh load from the source.
    case ignoreCachedData

    /// Reloads and revalidates cached data.
    ///
    /// The stored response is confirmed with the origin first, through its `ETag` or `Last-Modified`,
    /// and used if the origin says it did not change, whatever its freshness. One with no validator
    /// is loaded again.
    case reloadAndValidateCachedData

    /// Returns cached data if it is fresh, otherwise performs a load from the source.
    ///
    /// A response that is not fresh is not used, but it is kept, for ``useCachedDataOnly`` to give
    /// if the load fails.
    case returnCachedDataElseLoad

    /// Uses only cached data and doesn't make any network requests.
    ///
    /// Whatever is stored is given, however old: the freshness of the response is not looked at, and
    /// it is not removed for its age. The one exception is a stale response that must be
    /// validated before it is used (`must-revalidate`, or `no-cache`): it is not given, and is not
    /// removed either. When nothing usable is stored the request fails with ``EmptyCachedDataError``.
    case useCachedDataOnly
}
