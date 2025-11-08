/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsClientManagerTests {

    @Test
    func manager_whenRegister_shouldBeEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
        let provider = Internals.SharedSessionProvider()
        let configuration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            configuration: configuration
        )

        let sut2 = try await manager.client(
            provider: provider,
            configuration: configuration
        )

        // Then
        #expect(sut1 === sut2)
    }

    @Test
    func manager_whenRegisterWithDifferentConfiguration_shouldBeNotEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
        let provider = Internals.SharedSessionProvider()

        let configuration1 = Internals.Session.Configuration()

        var configuration2 = Internals.Session.Configuration()
        configuration2.timeout.connect = .seconds(1_000)

        // When
        let sut1 = try await manager.client(
            provider: provider,
            configuration: configuration1
        )

        let sut2 = try await manager.client(
            provider: provider,
            configuration: configuration2
        )

        // Then
        #expect(sut1 !== sut2)
    }

    @Test
    func manager_expiringClients() async throws {
        // Given
        let lifetime: UInt64 = 2_500_000_000
        let manager = Internals.ClientManager(lifetime: lifetime)
        let provider = Internals.SharedSessionProvider()
        let configuration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            configuration: configuration
        )

        try await _Concurrency.Task.sleep(nanoseconds: lifetime * 3)

        let sut2 = try await manager.client(
            provider: provider,
            configuration: configuration
        )

        // Then
        #expect(sut1 !== sut2)
    }
}
