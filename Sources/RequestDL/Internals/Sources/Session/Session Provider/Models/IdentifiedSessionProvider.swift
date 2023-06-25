/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
#if canImport(Network)
import NIOTransportServices
#else
import NIOPosix
#endif

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
            #if canImport(Network)
            return NIOTSEventLoopGroup(loopCount: numberOfThreads, defaultQoS: .default)
            #else
            return MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
            #endif
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
