/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOPosix

extension Internals {

    struct IdentifiedSessionProvider: SessionProvider {

        private let _id: String
        let numberOfThreads: Int

        init(id: String, numberOfThreads: Int) {
            self._id = id
            self.numberOfThreads = numberOfThreads
        }

        var id: String {
            "\(_id).\(numberOfThreads)"
        }

        func group() -> EventLoopGroup {
            MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
        }
    }
}

extension SessionProvider where Self == Internals.IdentifiedSessionProvider {

    static func identified(_ id: String, numberOfThreads: Int) -> Internals.IdentifiedSessionProvider {
        Internals.IdentifiedSessionProvider(
            id: id,
            numberOfThreads: numberOfThreads
        )
    }
}
