//
// See LICENSE for this package's licensing information.
//

/// The subset of ``CacheHeader`` directives that carry a defined meaning on a *request*
/// (RFC 7234 §5.2.1) and are therefore consumed by the local cache engine, not just serialized
/// onto the wire.
struct RequestCacheDirectives: Sendable, Hashable {

    var isStoringAllowed = true

    var requiresRevalidation = false

    var isOnlyIfCached = false
}
