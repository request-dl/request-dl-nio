//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOPosix
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals

#if canImport(Darwin)
import NIOTransportServices
#endif

@Suite(.concurrent(2))
struct SharedSessionProviderTests {

    @Test
    func sharedSessionProvider_whenIncompatibleWithNetworkFramework_shouldUseTheMultiThreadedGroup() {
        // Given
        let provider = Internals.SharedSessionProvider()
        let options = SessionProviderOptions(isCompatibleWithNetworkFramework: false)

        // Then
        #expect(provider.uniqueIdentifier(with: options) == provider.id)
        #expect(provider.group(with: options) is MultiThreadedEventLoopGroup)
    }

    @Test
    func sharedSessionProvider_whenCompatibleWithNetworkFramework_shouldReflectThePlatform() {
        // Given
        let provider = Internals.SharedSessionProvider()
        let options = SessionProviderOptions(isCompatibleWithNetworkFramework: true)

        #if canImport(Darwin)
        // Then
        #expect(provider.uniqueIdentifier(with: options) == "NTW." + provider.id)
        #expect(provider.group(with: options) is NIOTSEventLoopGroup)
        #else
        // Then
        #expect(provider.uniqueIdentifier(with: options) == provider.id)
        #expect(provider.group(with: options) is MultiThreadedEventLoopGroup)
        #endif
    }

    @Test
    func sharedSessionProvider_id_isStableAcrossInstances() {
        #expect(Internals.SharedSessionProvider().id == Internals.SharedSessionProvider().id)
    }
}
