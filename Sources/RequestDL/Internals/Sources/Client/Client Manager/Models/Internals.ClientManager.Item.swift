//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.DispatchTime
#endif

extension Internals.ClientManager {

    struct Item: Sendable {

        // MARK: - Internal properties

        let sessionConfiguration: Internals.Session.Configuration
        let client: Internals.Client

        /// Monotonic. See ``Internals/ClientManager/cleanupIfNeeded()`` for why this is not a
        /// `Date`.
        let readAt: UInt64

        // MARK: - Internal static methods

        static func createNew(
            sessionConfiguration: Internals.Session.Configuration,
            client: Internals.Client
        ) -> Internals.ClientManager.Item {
            .init(
                sessionConfiguration: sessionConfiguration,
                client: client,
                readAt: DispatchTime.now().uptimeNanoseconds
            )
        }

        // MARK: - Internal methods

        func updatingReadAt() -> Internals.ClientManager.Item {
            .init(
                sessionConfiguration: sessionConfiguration,
                client: client,
                readAt: DispatchTime.now().uptimeNanoseconds
            )
        }
    }
}
