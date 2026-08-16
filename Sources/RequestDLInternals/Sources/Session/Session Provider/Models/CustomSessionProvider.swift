//
// See LICENSE for this package's licensing information.
//

import NIOCore

extension Internals {

    package struct CustomSessionProvider: SessionProvider {

        // MARK: - Internal properties

        package var id: String {
            "\(ObjectIdentifier(_group))"
        }

        // MARK: - Private properties

        private let _group: EventLoopGroup

        // MARK: - Inits

        package init(_ group: EventLoopGroup) {
            self._group = group
        }

        // MARK: - Internal methods

        package func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            id
        }

        package func group(with options: SessionProviderOptions) -> any EventLoopGroup {
            _group
        }
    }
}

// MARK: - SessionProvider extension

extension SessionProvider where Self == Internals.CustomSessionProvider {

    package static func custom(_ group: EventLoopGroup) -> Internals.CustomSessionProvider {
        Internals.CustomSessionProvider(group)
    }
}
