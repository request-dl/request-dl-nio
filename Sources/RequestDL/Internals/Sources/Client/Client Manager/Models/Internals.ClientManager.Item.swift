/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals.ClientManager {

    struct Item {
        let configuration: Internals.Session.Configuration
        let client: Internals.Client
        let readAt: Date
    }
}

extension Internals.ClientManager.Item {

    static func createNew(
        configuration: Internals.Session.Configuration,
        client: Internals.Client
    ) -> Internals.ClientManager.Item {
        .init(
            configuration: configuration,
            client: client,
            readAt: .init()
        )
    }

    func updatingReadAt() -> Internals.ClientManager.Item {
        .init(
            configuration: configuration,
            client: client,
            readAt: .init()
        )
    }
}
