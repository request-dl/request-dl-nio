/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct CustomSessionProvider: SessionProvider {

        // MARK: - Internal properties

        var id: String {
            "\(ObjectIdentifier(_group))"
        }

        // MARK: - Private properties

        private let _group: EventLoopGroup

        // MARK: - Inits

        init(_ group: EventLoopGroup) {
            self._group = group
        }

        // MARK: - Internal methods

        func group() -> EventLoopGroup {
            _group
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.CustomSessionProvider {

    static func custom(_ group: EventLoopGroup) -> Internals.CustomSessionProvider {
        Internals.CustomSessionProvider(group)
    }
}
