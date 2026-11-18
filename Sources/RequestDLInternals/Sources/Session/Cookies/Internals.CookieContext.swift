//
// See LICENSE for this package's licensing information.
//

import Foundation

extension Internals {

    /// What an executor needs to take part in a cookie jar for the duration of one request: where
    /// to store what each response head says, and whether it is the one writing the `Cookie`
    /// header, which it then has to recompute on every redirect hop.
    ///
    /// Travels with the request, not with the pooled client: a client is shared by requests that
    /// have different jars, or none.
    package struct CookieContext: Sendable {

        // MARK: - Internal properties

        package let storage: CookieStorage

        /// `true` when the jar wrote the `Cookie` header of this request, so it also owns the
        /// one of each redirect hop. `false` when the caller set a `Cookie` header themselves:
        /// the jar still stores what the responses set, but never replaces what was asked for.
        package let managesHeader: Bool

        // MARK: - Inits

        package init(storage: CookieStorage, managesHeader: Bool) {
            self.storage = storage
            self.managesHeader = managesHeader
        }

        // MARK: - Internal methods

        /// Stores the `Set-Cookie` fields among `fields`, as the response to a request to `url`.
        ///
        /// Each hop is stored with the URL of its own request: a cookie set by a redirect's target
        /// belongs to the target's host, not to the host the request started at.
        package func store(headerFields fields: some Sequence<(name: String, value: String)>, for url: URL) {
            let values = fields
                .filter { $0.name.lowercased() == "set-cookie" }
                .map(\.value)

            guard !values.isEmpty else {
                return
            }

            storage.store(setCookieValues: values, for: url)
        }

        /// The `Cookie` header value a redirect hop to `url` is owed, when the jar owns it.
        package func cookieHeaderForRedirect(to url: URL) -> String? {
            managesHeader ? storage.cookieHeader(for: url) : nil
        }
    }
}
