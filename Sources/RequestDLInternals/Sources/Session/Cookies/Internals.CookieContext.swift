//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

        /// The `Cookie` header the request itself was sent with, which is what a cached response is
        /// recorded as having been fetched with.
        package let initialCookieHeader: String?

        private let trace = Trace()

        // MARK: - Inits

        package init(storage: CookieStorage, managesHeader: Bool, initialCookieHeader: String? = nil) {
            self.storage = storage
            self.managesHeader = managesHeader
            self.initialCookieHeader = initialCookieHeader
        }

        // MARK: - Internal properties

        /// Whether a redirect hop was sent cookies that the request itself was not: the response
        /// at the end of the chain was fetched with credentials the cache never saw.
        ///
        /// A cache that records the request's credentials with a stored response, and gives it
        /// only to a request that sends them, would store this one as the response of whoever sent
        /// none, and hand it to anyone, so it is not stored.
        package var hasSentCookiesTheRequestDidNot: Bool {
            trace.value
        }

        // MARK: - Private types

        private final class Trace: @unchecked Sendable {

            private let lock = Lock()
            private var _value = false

            var value: Bool {
                lock.lock()
                defer { lock.unlock() }
                return _value
            }

            func mark() {
                lock.lock()
                defer { lock.unlock() }
                _value = true
            }
        }

        // MARK: - Internal methods

        /// Stores the `Set-Cookie` fields among `fields`, as the response to a request to `url`.
        ///
        /// Each hop is stored with the URL of its own request: a cookie set by a redirect's target
        /// belongs to the target's host, not to the host the request started at.
        ///
        /// - Parameter areFolded: See ``Internals/CookieStorage/store(setCookieValues:for:areFolded:now:)``.
        package func store(
            headerFields fields: some Sequence<(name: String, value: String)>,
            for url: URL,
            areFolded: Bool = false
        ) {
            let values =
                fields
                .filter { $0.name.lowercased() == "set-cookie" }
                .map(\.value)

            guard !values.isEmpty else {
                return
            }

            storage.store(setCookieValues: values, for: url, areFolded: areFolded)
        }

        /// The `Cookie` header value a redirect hop to `url` is owed, when the jar owns the header,
        /// remembering when it is something the request itself did not send.
        package func cookieHeaderForHop(to url: URL) -> String? {
            let value = cookieHeader(for: url)

            if let value, value != initialCookieHeader {
                trace.mark()
            }

            return value
        }

        /// The `Cookie` header value a request to `url` is owed right now, when the jar owns the
        /// header: for a redirect hop, and for a request sent after the first one finished.
        package func cookieHeader(for url: URL) -> String? {
            managesHeader ? storage.cookieHeader(for: url) : nil
        }
    }
}
