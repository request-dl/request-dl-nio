/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InternalsClientManagerTests: XCTestCase {

    func testManager_whenRegister_shouldBeEqual() async throws {
        // Given
        let manager = await Internals.ClientManager.shared
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
        XCTAssertTrue(sut1 === sut2)
    }

    func testManager_whenRegisterWithDifferentConfiguration_shouldBeNotEqual() async throws {
        // Given
        let manager = await Internals.ClientManager.shared
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
        XCTAssertFalse(sut1 === sut2)
    }

    func testManager_expiringClients() async throws {
        // Given
        let lifetime: UInt64 = 1_000_000_000
        let manager = await Internals.ClientManager(lifetime: lifetime)
        let provider = Internals.SharedSessionProvider()
        let configuration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            configuration: configuration
        )

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime * 2))

        let sut2 = try await manager.client(
            provider: provider,
            configuration: configuration
        )

        // Then
        XCTAssertFalse(sut1 === sut2)
    }
}
