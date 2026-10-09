//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import SwiftAsyncStream

extension Internals {

    /// The origins a client's mTLS identity may be presented to: the ones requests were made to.
    ///
    /// `Internals.Client` records the origin of every request it executes, and the identity
    /// provider installed on `HTTPClient.Configuration` answers only for those. A redirect is
    /// followed inside AsyncHTTPClient, never through `Internals.Client.execute`, so a redirect
    /// to another host or port is not in here, and gets no identity. That is the model of
    /// `URLSession`'s authentication challenge, which `Internals.URLSessionIdentityPolicy`
    /// already follows for `.urlSession`.
    ///
    /// An origin stays recorded for the life of the client, so a later redirect back to an
    /// origin that was requested directly is still given the identity: the caller addressed that
    /// origin itself with this session.
    package final class IdentityOrigins: @unchecked Sendable {

        private struct Origin: Hashable {
            let host: String
            let port: Int
        }

        private let lock = Lock()
        private var origins: Set<Origin> = []

        package init() {}

        /// Records an origin a request is being made to.
        package func register(host: String, port: Int) {
            let origin = Self.origin(host: host, port: port)
            lock.withLock { _ = origins.insert(origin) }
        }

        /// Whether a request was made to this origin.
        package func contains(host: String, port: Int) -> Bool {
            let origin = Self.origin(host: host, port: port)
            return lock.withLock { origins.contains(origin) }
        }

        /// Host names compare without regard to case, and an IPv6 literal without its brackets,
        /// which is how AsyncHTTPClient hands it to the provider.
        private static func origin(host: String, port: Int) -> Origin {
            var host = host.lowercased()

            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }

            return Origin(host: host, port: port)
        }
    }
}

#endif
