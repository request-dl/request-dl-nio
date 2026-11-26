//
// See LICENSE for this package's licensing information.
//

private struct HiddenOnRedirectKey: RequestEnvironmentKey {
    static let defaultValue: RedirectHeaderScope? = nil
}

extension RequestEnvironmentValues {

    var hiddenOnRedirect: RedirectHeaderScope? {
        get { self[HiddenOnRedirectKey.self] }
        set { self[HiddenOnRedirectKey.self] = newValue }
    }
}

extension Property {

    ///
    /// Marks the headers of the property as ones that must not follow a redirect.
    ///
    /// When a request is redirected, the executor sends the next one with the headers of the
    /// previous one, except for `Authorization`, `Proxy-Authorization`, `Cookie`, `Origin` and an
    /// explicit `Host`, which a redirect to another origin removes. Any other header is forwarded,
    /// a credential such as `X-Api-Key` included, since it is not known to be one. Use this to name
    /// the headers that must not reach the destination of a redirect.
    ///
    /// ```swift
    /// CustomHeader(name: "X-Api-Key", value: key)
    ///     .hiddenOnRedirect()
    /// ```
    ///
    /// It applies to every header the property declares, so it can be used on a ``HeaderGroup``:
    ///
    /// ```swift
    /// HeaderGroup {
    ///     CustomHeader(name: "X-Api-Key", value: key)
    ///     CustomHeader(name: "X-Tenant-Token", value: token)
    /// }
    /// .hiddenOnRedirect(.anyRedirect)
    /// ```
    ///
    /// The header names are compared without regard to case. The first request is never changed:
    /// only the requests sent after a redirect lose the header. It works the same with every
    /// executor, with a ``RedirectStrategy`` included, which is handed the request already without
    /// the header and cannot add it back for a redirect that must not carry it.
    ///
    /// - Parameter scope: Which redirects remove the header. Defaults to
    /// ``RedirectHeaderScope/otherOrigins``.
    /// - Returns: A modified version of the property whose headers are removed from the redirects
    /// `scope` names.
    ///
    public func hiddenOnRedirect(_ scope: RedirectHeaderScope = .otherOrigins) -> some Property {
        environment(\.hiddenOnRedirect, scope)
    }
}
