/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOPosix

extension Internals {

    struct SharedSessionProvider: SessionProvider {

        // MARK: - Internal properties

        var id: String {
            "\(ObjectIdentifier(Self.self))"
        }

        // MARK: - Internal methods

        func group() -> EventLoopGroup {
            MultiThreadedEventLoopGroup.shared
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.SharedSessionProvider {

    static var shared: Internals.SharedSessionProvider {
        Internals.SharedSessionProvider()
    }
}
