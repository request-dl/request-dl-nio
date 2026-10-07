//
// See LICENSE for this package's licensing information.
//

extension Proxy {

    /// Deprecated: `Authorization` never used `Headers`, but being a `struct` nested inside the
    /// generic `Proxy<Headers>` made `Proxy<A>.Authorization` and `Proxy<B>.Authorization`
    /// formally different types, a trap for code referencing the type outside a context where
    /// `Headers` is already pinned by argument inference (e.g. a standalone helper function).
    /// Use the top-level ``ProxyAuthorization`` instead: as a `typealias` (not a new nominal
    /// type), `Proxy<Headers>.Authorization` now resolves to the same ``ProxyAuthorization``
    /// regardless of `Headers`.
    @available(*, deprecated, renamed: "ProxyAuthorization")
    public typealias Authorization = ProxyAuthorization
}
