/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
#if canImport(Darwin)
import NIOTransportServices
#endif
import NIOPosix

extension Internals {

    struct SharedSessionProvider: SessionProvider {

        // MARK: - Internal properties

        var id: String {
            "\(ObjectIdentifier(Self.self))"
        }

        // MARK: - Internal methods

        func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            #if canImport(Darwin)
            if options.isCompatibleWithNetworkFramework {
                return "NTW." + id
            }
            #endif
            return id
        }

        func group(with options: SessionProviderOptions) -> EventLoopGroup {
            #if canImport(Darwin)
            if options.isCompatibleWithNetworkFramework {
                return NIOTSEventLoopGroup.shared
            }
            #endif
            return MultiThreadedEventLoopGroup.shared
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.SharedSessionProvider {

    static var shared: Internals.SharedSessionProvider {
        Internals.SharedSessionProvider()
    }
}
