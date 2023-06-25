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

    struct SharedSessionProvider: SessionProvider {

        // MARK: - Internal properties

        var id: String {
            "\(ObjectIdentifier(Self.self))"
        }

        // MARK: - Internal methods

        func group() -> EventLoopGroup {
            #if canImport(Network)
            return NIOTSEventLoopGroup.shared
            #else
            return MultiThreadedEventLoopGroup.shared
            #endif
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.SharedSessionProvider {

    static var shared: Internals.SharedSessionProvider {
        Internals.SharedSessionProvider()
    }
}
