//
// See LICENSE for this package's licensing information.
//

import NIOCore

package protocol SessionProvider: Sendable {

    func uniqueIdentifier(
        with options: SessionProviderOptions
    ) -> String

    func group(
        with options: SessionProviderOptions
    ) -> EventLoopGroup
}

package struct SessionProviderOptions: Sendable {
    package let isCompatibleWithNetworkFramework: Bool

    package init(isCompatibleWithNetworkFramework: Bool) {
        self.isCompatibleWithNetworkFramework = isCompatibleWithNetworkFramework
    }
}
