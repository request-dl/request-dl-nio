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
        package let client: Internals.ClientManager.Client

        #if canImport(Darwin)
        /// Monotonic. See ``Internals/ClientManager/cleanupIfNeeded()`` for why this is not a
        /// `Date`.
        package let readAt: UInt64
        #else
        package let readAt: ContinuousClock.Instant
        #endif

        /// `client.operationGeneration` as of `readAt`. Compared back against the client's
        /// *current* generation by the idle-cleanup sweep and ceiling eviction: a mismatch means
        /// an operation has completed since this item was last touched -- e.g. between two
        /// sequential calls on the same resolved client -- so the client was genuinely active
        /// more recently than `readAt` alone would suggest, even though nothing is running on it
        /// at this exact instant. See `Internals.ClientOperationQueue.generation`'s own doc
        /// comment for the full rationale.
        package let lastKnownOperationGeneration: UInt64

        // MARK: - Internal static methods

        package static func createNew(
            sessionConfiguration: Internals.Session.Configuration,
            client: Internals.ClientManager.Client
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
                }(),
                lastKnownOperationGeneration: client.operationGeneration
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
                }(),
                lastKnownOperationGeneration: client.operationGeneration
            )
        }
    }
}
