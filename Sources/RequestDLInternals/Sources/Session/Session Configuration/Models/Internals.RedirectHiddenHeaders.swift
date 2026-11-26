//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// The headers a caller marked, with `hiddenOnRedirect(_:)`, as not to follow a redirect, which
    /// every redirect hop of either executor is checked against. See ``Internals/RedirectSanitizer``.
    ///
    /// Names are stored lowercased: header names are case-insensitive.
    ///
    /// Part of `Internals.Session.Configuration.==`: a pooled client follows redirects with the
    /// names it was built with.
    package struct RedirectHiddenHeaders: Sendable, Hashable {

        // MARK: - Package properties

        /// Removed from a hop that goes to another origin, as the built-in credential headers are.
        package private(set) var otherOrigins: Set<String> = []

        /// Removed from every hop, a hop that stays on the origin included.
        package private(set) var anyRedirect: Set<String> = []

        package var isEmpty: Bool {
            otherOrigins.isEmpty && anyRedirect.isEmpty
        }

        // MARK: - Inits

        package init() {}

        // MARK: - Package methods

        /// Marks `name` as not to follow a redirect.
        ///
        /// A name marked for both scopes is removed on every hop: `anyRedirect` is the wider one.
        package mutating func insert(name: String, onAnyRedirect: Bool) {
            let name = name.lowercased()

            guard !name.isEmpty else {
                return
            }

            if onAnyRedirect {
                anyRedirect.insert(name)
            } else {
                otherOrigins.insert(name)
            }
        }
    }
}
