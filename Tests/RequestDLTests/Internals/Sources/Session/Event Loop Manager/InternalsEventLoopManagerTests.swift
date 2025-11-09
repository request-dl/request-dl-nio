/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOCore
import NIOPosix
@testable import RequestDL

struct InternalsEventLoopManagerTests {

    struct CustomProvider: SessionProvider {

        let id = "test"
        private let _group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            id
        }

        func group(with options: SessionProviderOptions) -> EventLoopGroup {
            _group
        }
    }

    var options: SessionProviderOptions {
        SessionProviderOptions(
            isCompatibleWithNetworkFramework: true
        )
    }

    @Test
    func manager_whenRegisterGroup_shouldBeResolved() async throws {
        // Given
        let manager = Internals.EventLoopGroupManager()
        let provider = CustomProvider()

        // When
        let sut1 = await manager.provider(provider, with: options)

        // Then
        #expect(provider.group(with: options) === sut1)
    }

    @Test
    func manager_whenRegisterIdentifier_shouldBeResolvedOnlyOnce() async throws {
        // Given
        let provider = CustomProvider()
        let manager = Internals.EventLoopGroupManager()

        // When
        let sut1 = await manager.provider(provider, with: options)
        let sut2 = await manager.provider(provider, with: options)

        // Then
        #expect(provider.group(with: options) === sut1)
        #expect(provider.group(with: options) === sut2)
    }

    @Test
    func manager_whenRunningInBackground() async throws {
        // Given
        let provider = CustomProvider()
        let manager = Internals.EventLoopGroupManager()

        // When
        let sut = await _Concurrency.Task.detached(priority: .background) { [manager, options] in
            await manager.provider(provider, with: options)
        }.value

        // Then
        #expect(sut === provider.group(with: options))
    }
}
