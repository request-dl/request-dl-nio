//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOPosix

#if canImport(Darwin)
import NIOTransportServices
#endif

extension Internals {

    package struct IdentifiedSessionProvider: SessionProvider {

        // MARK: - Internal properties

        package var id: String {
            "\(storedID).\(numberOfThreads)"
        }

        package let numberOfThreads: Int

        // MARK: - Private properties

        private let storedID: String

        // MARK: - Inits

        package init(id: String, numberOfThreads: Int) {
            self.storedID = id
            self.numberOfThreads = numberOfThreads
        }

        // MARK: - Internal methods

        package func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            #if canImport(Darwin)
            if options.isCompatibleWithNetworkFramework {
                return "NTW." + id
            }
            #endif
            return id
        }

        package func group(with options: SessionProviderOptions) -> any EventLoopGroup {
            #if canImport(Darwin)
            if options.isCompatibleWithNetworkFramework {
                return NIOTSEventLoopGroup(loopCount: numberOfThreads, defaultQoS: .default)
            }
            #endif
            return MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.IdentifiedSessionProvider {

    package static func identified(_ id: String, numberOfThreads: Int) -> Internals.IdentifiedSessionProvider {
        Internals.IdentifiedSessionProvider(
            id: id,
            numberOfThreads: numberOfThreads
        )
    }
}
