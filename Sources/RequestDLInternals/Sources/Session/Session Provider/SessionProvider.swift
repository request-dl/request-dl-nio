//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOCore
#endif

/// A provider of whatever identity/event-loop-group backing a `.nio`/`.nioTransportServices`
/// connection needs: `uniqueIdentifier(with:)` is also used for `.urlSession` cache-keying, so
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

    /// Whether `group(with:)` *builds* the group it hands back, making that group
    /// `Internals.EventLoopGroupManager`'s to shut down once it stops tracking it.
    ///
    /// `false` for anything that returns a group it merely borrows: NIO's process-wide
    /// singletons (`Internals.SharedSessionProvider`) and a group the caller constructed and
    /// handed in through `Session.init(_:)` (`Internals.CustomSessionProvider`). Shutting either
    /// of those down would take every unrelated user of the same group with it.
    ///
    /// Defaults to `false`, so a provider that says nothing is never assumed to have handed over
    /// ownership of something it may not own.
    var createsGroup: Bool { get }
    #endif
}

#if canImport(NIOCore)
extension SessionProvider {

    package var createsGroup: Bool { false }
}
#endif

package struct SessionProviderOptions: Sendable {
    package let isCompatibleWithNetworkFramework: Bool

    package init(isCompatibleWithNetworkFramework: Bool) {
        self.isCompatibleWithNetworkFramework = isCompatibleWithNetworkFramework
    }
}
