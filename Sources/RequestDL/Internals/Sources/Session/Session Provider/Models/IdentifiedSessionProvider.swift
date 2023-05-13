/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOPosix

extension Internals {

    struct IdentifiedSessionProvider: SessionProvider {

        // MARK: - Internal properties

        var id: String {
            "\(storedID).\(numberOfThreads)"
        }

        let numberOfThreads: Int

        // MARK: - Private properties

        private let storedID: String

        // MARK: - Inits

        init(id: String, numberOfThreads: Int) {
            self.storedID = id
            self.numberOfThreads = numberOfThreads
        }

        // MARK: - Internal methods

        func group() -> EventLoopGroup {
            MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.IdentifiedSessionProvider {

    static func identified(_ id: String, numberOfThreads: Int) -> Internals.IdentifiedSessionProvider {
        Internals.IdentifiedSessionProvider(
            id: id,
            numberOfThreads: numberOfThreads
        )
    }
}
