//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDL

struct InternalsClientManagerTests {

    @Test
    func manager_whenRegister_shouldBeEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        #expect(sut1 === sut2)
    }

    @Test
    func manager_whenRegisterWithDifferentConfiguration_shouldBeNotEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
        let provider = Internals.SharedSessionProvider()

        let sessionConfiguration1 = Internals.Session.Configuration()

        var sessionConfiguration2 = Internals.Session.Configuration()
        sessionConfiguration2.timeout.connect = .seconds(1_000)

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration1
        )

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration2
        )

        // Then
        #expect(sut1 !== sut2)
    }

    @Test
    func manager_expiringClients() async throws {
        // Given
        let lifetime = TimeAmount.seconds(2) + .milliseconds(500)
        let manager = Internals.ClientManager(lifetime: lifetime)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime.nanoseconds) * 3)

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        #expect(sut1 !== sut2)
    }

    @Test
    func manager_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: .seconds(5 * 60))
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        // `AsyncLock` never aborts acquisition, so this only fails if `client(provider:
        // sessionConfiguration:)` checks cancellation itself once inside the lock.
        let task = _Concurrency.Task<Internals.Client, Error> {
            try await manager.client(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }
        task.cancel()

        // Then
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
