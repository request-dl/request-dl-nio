//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOPosix

#if canImport(Darwin)
import NIOTransportServices
#endif

extension Internals {

    package struct SharedSessionProvider: SessionProvider {

        // MARK: - Internal properties

        package var id: String {
            "\(ObjectIdentifier(Self.self))"
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

        package func group(with options: SessionProviderOptions) -> EventLoopGroup {
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

    package static var shared: Internals.SharedSessionProvider {
        Internals.SharedSessionProvider()
    }
}
