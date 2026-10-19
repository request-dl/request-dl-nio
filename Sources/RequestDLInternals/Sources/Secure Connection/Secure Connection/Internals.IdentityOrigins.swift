//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// The origins a client's mTLS identity may be presented to: the ones requests were made to.
    ///
    /// Both executors record the origin of every request they execute, and answer only for
    /// those: `Internals.Client` for `.nio` and `.nioTransportServices`, where the identity
    /// providers installed on `HTTPClient.Configuration` consult it, and
    /// `Internals.URLSessionClient` for `.urlSession`, where its `TLSDelegate` does. A redirect is
    /// followed inside the transport, never through `execute`, so a redirect to another host or
    /// port is not in here, and gets no identity.
    ///
    /// An origin stays recorded for the life of the client, so a later redirect back to an
    /// origin that was requested directly is still given the identity: the caller addressed that
    /// origin itself with this session. It is the same on both executors.
    package final class IdentityOrigins: @unchecked Sendable {

        private let lock = Lock()
        private var origins: Set<Internals.IdentityOrigin> = []

        package init() {}

        /// Records an origin a request is being made to.
        package func register(host: String, port: Int) {
            register(Internals.IdentityOrigin(host: host, port: port))
        }

        package func register(_ origin: Internals.IdentityOrigin) {
            lock.withLock { _ = origins.insert(origin) }
        }

        /// Whether a request was made to this origin.
        package func contains(host: String, port: Int) -> Bool {
            contains(Internals.IdentityOrigin(host: host, port: port))
        }

        package func contains(_ origin: Internals.IdentityOrigin) -> Bool {
            lock.withLock { origins.contains(origin) }
        }
    }
}
