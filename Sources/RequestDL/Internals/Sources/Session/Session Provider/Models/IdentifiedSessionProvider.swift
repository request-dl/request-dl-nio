/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
#if os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS)
import NIOTransportServices
#endif
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

        func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            #if os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS)
            if options.isCompatibleWithNetworkFramework {
                return "NTS." + id
            }
            #endif
            return id
        }

        func group(with options: SessionProviderOptions) -> any EventLoopGroup {
            #if os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS)
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

    static func identified(_ id: String, numberOfThreads: Int) -> Internals.IdentifiedSessionProvider {
        Internals.IdentifiedSessionProvider(
            id: id,
            numberOfThreads: numberOfThreads
        )
    }
}
