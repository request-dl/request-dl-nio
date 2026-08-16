//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
#if canImport(Darwin)
import struct Foundation.DispatchTime
#endif
#endif

extension Internals.ClientManager {

    package struct Item: Sendable {

        // MARK: - Internal properties

        package let sessionConfiguration: Internals.Session.Configuration
        package let client: Internals.Client

        #if canImport(Darwin)
        /// Monotonic. See ``Internals/ClientManager/cleanupIfNeeded()`` for why this is not a
        /// `Date`.
        package let readAt: UInt64
        #else
        package let readAt: ContinuousClock.Instant
        #endif

        // MARK: - Internal static methods

        package static func createNew(
            sessionConfiguration: Internals.Session.Configuration,
            client: Internals.Client
        ) -> Internals.ClientManager.Item {
            .init(
                sessionConfiguration: sessionConfiguration,
                client: client,
                readAt: {
                    #if canImport(Darwin)
                    DispatchTime.now().uptimeNanoseconds
                    #else
                    ContinuousClock.now
                    #endif
                }()
            )
        }

        // MARK: - Internal methods

        package func updatingReadAt() -> Internals.ClientManager.Item {
            .init(
                sessionConfiguration: sessionConfiguration,
                client: client,
                readAt: {
                    #if canImport(Darwin)
                    DispatchTime.now().uptimeNanoseconds
                    #else
                    ContinuousClock.now
                    #endif
                }()
            )
        }
    }
}
