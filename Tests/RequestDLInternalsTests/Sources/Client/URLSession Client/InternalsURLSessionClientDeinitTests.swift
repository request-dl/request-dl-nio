//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import SwiftAsyncStream

/// A client that nothing refers to anymore has to take its `URLSession` with it: a session stays alive
/// until it is told to end, and `Internals.ClientManager` retires an unpooled, evicted or expired client
/// simply by letting go of it.
///
/// The session is private and, once the client is gone, unreachable. The one thing it reports about its own
/// end is `urlSession(_:didBecomeInvalidWithError:)`, so these tests hand the client a session delegate and
/// wait for that, rather than asserting that the client was released (which holds with or without `deinit`
/// doing anything to the session).
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsURLSessionClientDeinitTests {

    /// Only the failing outcome ever waits this long: a session that is invalidated reports it at once.
    private static let timeout: UInt64 = 30_000_000_000

    @Test
    func deinit_whenTheLastReferenceGoes_invalidatesTheSession() async throws {
        // Given
        let probe = SessionInvalidationProbe()

        // When: the client is out of scope without ever having been shut down.
        try autoreleasepool {
            let client = try Internals.URLSessionClient(
                configuration: .ephemeral,
                sessionDelegate: probe
            )

            #expect(!probe.isInvalidated)
            withExtendedLifetime(client) {}
        }

        // Then
        #expect(await probe.waitForInvalidation(timeout: Self.timeout))
    }

    /// Pins the seam itself: that the probe sees an invalidation at all, and that it does so for the
    /// path `deinit` is not meant to repeat.
    @Test
    func shutdown_invalidatesTheSessionWithoutWaitingForTheClientToGo() async throws {
        // Given
        let probe = SessionInvalidationProbe()
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            sessionDelegate: probe
        )

        // When
        #expect(try await client.shutdown())

        // Then: while the client is still alive.
        #expect(await probe.waitForInvalidation(timeout: Self.timeout))
        withExtendedLifetime(client) {}
    }
}

/// Reports a session becoming invalid. The session holds its delegate until then, which is what lets the
/// probe outlive the client under test.
private final class SessionInvalidationProbe: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let signal = AsyncSignal()
    private let lock = Lock()
    private var _isInvalidated = false

    var isInvalidated: Bool {
        lock.withLock { _isInvalidated }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        lock.withLock { _isInvalidated = true }
        signal.signal()
    }

    /// - Returns: `false` if the session had not reported being invalidated after `timeout` nanoseconds.
    func waitForInvalidation(timeout: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { [signal] in
                (try? await signal.wait()) != nil
            }

            group.addTask {
                try? await _Concurrency.Task.sleep(nanoseconds: timeout)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

#endif
