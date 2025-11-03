/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

protocol SessionProvider: Sendable {

    func uniqueIdentifier(
        with options: SessionProviderOptions
    ) -> String

    func group(
        with options: SessionProviderOptions
    ) -> EventLoopGroup
}

struct SessionProviderOptions: Sendable {
    let isCompatibleWithNetworkFramework: Bool
}
