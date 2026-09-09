//
// See LICENSE for this package's licensing information.
//

extension Proxy {

    /// Deprecated: `Authorization` never used `Headers`, but being declared as a `struct` nested
    /// inside the generic `Proxy<Headers>` meant `Proxy<A>.Authorization` and
    /// `Proxy<B>.Authorization` were formally different types to the compiler — a trap for any
    /// code referencing the type outside a context where `Headers` is already pinned by argument
    /// inference (e.g. a standalone helper function). Use the top-level ``ProxyAuthorization``
    /// instead: as a `typealias` (not a new nominal type), `Proxy<Headers>.Authorization` now
    /// resolves to the same ``ProxyAuthorization`` regardless of `Headers`.
    @available(*, deprecated, renamed: "ProxyAuthorization")
    public typealias Authorization = ProxyAuthorization
}
