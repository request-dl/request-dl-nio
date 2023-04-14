/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOPosix

extension Internals {

    struct SharedSessionProvider: SessionProvider {

        var id: String {
            "\(ObjectIdentifier(Self.self))"
        }

        func group() -> EventLoopGroup {
            MultiThreadedEventLoopGroup.shared
        }
    }
}

extension SessionProvider where Self == Internals.SharedSessionProvider {

    static var shared: Internals.SharedSessionProvider {
        Internals.SharedSessionProvider()
    }
}
