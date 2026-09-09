//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Testing

@testable import RequestDLInternals

struct InternalsNetworkPathMonitorTests {

    @Test
    func monitor_whenSharedAccessedTwice_shouldReturnSameInstance() async throws {
        // Given
        let first = Internals.NetworkPathMonitor.shared
        let second = Internals.NetworkPathMonitor.shared

        // Then
        #expect(first === second)
    }

    @Test
    func monitor_updates_shouldYieldCurrentSnapshotImmediatelyOnSubscribe() async throws {
        // Given
        let monitor = Internals.NetworkPathMonitor.shared
        let expectedPath = monitor.currentPath

        // When
        var iterator = monitor.updates().makeAsyncIterator()
        let firstUpdate = await iterator.next()

        // Then
        #expect(firstUpdate == expectedPath)
    }

    @Test
    func monitor_updates_multipleConcurrentSubscribers_shouldEachReceiveTheirOwnFirstSnapshot() async throws {
        // Given
        let monitor = Internals.NetworkPathMonitor.shared

        // When
        async let first = monitor.updates().first { _ in true }
        async let second = monitor.updates().first { _ in true }

        let (firstResult, secondResult) = try await (first, second)

        // Then
        #expect(firstResult != nil)
        #expect(secondResult != nil)
    }
}
#endif
