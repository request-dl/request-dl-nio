//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct SharedSessionProviderTests {

    @Test
    func sharedSessionProvider_id_isStableAcrossInstances() {
        #expect(Internals.SharedSessionProvider().id == Internals.SharedSessionProvider().id)
    }
}

// `SessionProvider.group(with:)` (and every `EventLoopGroup` conformance it returns) only
// exists under `canImport(NIOCore)`.
#if canImport(NIOCore)

import NIOCore
import NIOPosix

#if canImport(Darwin)
import NIOTransportServices
#endif

extension SharedSessionProviderTests {

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
}

#endif
