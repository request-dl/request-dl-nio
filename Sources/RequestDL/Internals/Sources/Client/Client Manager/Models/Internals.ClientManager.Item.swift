//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.ClientManager {

    struct Item: Sendable {

        // MARK: - Internal properties

        let sessionConfiguration: Internals.Session.Configuration
        let client: Internals.Client
        let readAt: Date

        // MARK: - Internal static methods

        static func createNew(
            sessionConfiguration: Internals.Session.Configuration,
            client: Internals.Client
        ) -> Internals.ClientManager.Item {
            .init(
                sessionConfiguration: sessionConfiguration,
                client: client,
                readAt: .init()
            )
        }

        // MARK: - Internal methods

        func updatingReadAt() -> Internals.ClientManager.Item {
            .init(
                sessionConfiguration: sessionConfiguration,
                client: client,
                readAt: .init()
            )
        }
    }
}
