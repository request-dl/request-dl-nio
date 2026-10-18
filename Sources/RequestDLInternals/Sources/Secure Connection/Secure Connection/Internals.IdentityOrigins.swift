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

        private let lock = Lock()
        private var origins: Set<Internals.IdentityOrigin> = []

        package init() {}

        /// Records an origin a request is being made to.
        package func register(host: String, port: Int) {
            let origin = Internals.IdentityOrigin(host: host, port: port)
            lock.withLock { _ = origins.insert(origin) }
        }

        /// Whether a request was made to this origin.
        package func contains(host: String, port: Int) -> Bool {
            let origin = Internals.IdentityOrigin(host: host, port: port)
            return lock.withLock { origins.contains(origin) }
        }
    }
}

#endif
