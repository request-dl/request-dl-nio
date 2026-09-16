//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOCore
#endif

/// A provider of whatever identity/event-loop-group backing a `.nio`/`.nioTransportServices`
/// connection needs, `uniqueIdentifier(with:)` is also used for `.urlSession` cache-keying, so
/// it stays required regardless of NIO's availability. `group(with:)` only exists when NIO does:
/// there's nothing for it to build otherwise, and every conformer either lives in a NIO-only file
/// already (`Internals.CustomSessionProvider`) or gates its own implementation of this
/// requirement the same way (`Internals.IdentifiedSessionProvider`/`SharedSessionProvider`).
package protocol SessionProvider: Sendable {

    func uniqueIdentifier(
        with options: SessionProviderOptions
    ) -> String

    #if canImport(NIOCore)
    func group(
        with options: SessionProviderOptions
    ) -> EventLoopGroup
    #endif
}

package struct SessionProviderOptions: Sendable {
    package let isCompatibleWithNetworkFramework: Bool

    package init(isCompatibleWithNetworkFramework: Bool) {
        self.isCompatibleWithNetworkFramework = isCompatibleWithNetworkFramework
    }
}
