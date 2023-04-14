/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct CustomSessionProvider: SessionProvider {

        private let _group: EventLoopGroup

        init(_ group: EventLoopGroup) {
            self._group = group
        }

        var id: String {
            "\(ObjectIdentifier(_group))"
        }

        func group() -> EventLoopGroup {
            _group
        }
    }
}

extension SessionProvider where Self == Internals.CustomSessionProvider {

    static func custom(_ group: EventLoopGroup) -> Internals.CustomSessionProvider {
        Internals.CustomSessionProvider(group)
    }
}
