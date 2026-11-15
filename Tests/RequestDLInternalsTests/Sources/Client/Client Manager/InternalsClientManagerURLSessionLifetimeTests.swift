//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore) && canImport(Darwin)

import Foundation
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

/// An unpooled `.urlSession` client invalidates its session when the last reference goes, so a request that
/// still needs the session, after the call that started it has returned, has to be one of those references.
struct InternalsClientManagerURLSessionLifetimeTests {

    /// The exchange of a streamed request runs on its own `Task`, well past the call that started it, and
    /// touches the session again for every redirect that resends a body and every download reconnection.
    /// Nothing but the exchange refers to the client once the caller has let go of it, so if the exchange does
    /// not hold it, the session is invalidated underneath it: `NSGenericException`, and the process ends.
    ///
    /// A server that never answers keeps the exchange running for as long as the test needs, which makes
    /// "the client is still alive" something to observe rather than something to race.
    @Test
    func sessionTask_whenCallerDropsAnUnpooledClient_keepsItAliveUntilTheExchangeEnds() async throws {
        try await withHangingTCPServer { port in
            // Given
            let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
            let provider = Internals.SharedSessionProvider()

            var sessionConfiguration = Internals.Session.Configuration()
            sessionConfiguration.requiredExecutor = .urlSession
            sessionConfiguration.redirectConfiguration = .strategy(NeverFollowingRedirectStrategy())

            let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))

            // When: the client is out of scope as soon as the request has been started.
            let (sessionTask, weakClient) = try await {
                let resolved = try await manager.resolvedClient(
                    provider: provider,
                    sessionConfiguration: sessionConfiguration
                )

                guard case .urlSession(let client) = resolved else {
                    throw UnexpectedClient()
                }

                let sessionTask = try await client.execute(
                    request: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData),
                    readingMode: .length(1_024),
                    uploadingBytes: .zero,
                    decompression: .disabled,
                    cache: nil,
                    logger: nil
                )

                return (sessionTask, WeakURLSessionClient(client))
            }()

            // Then: nothing the test holds refers to the client, and still it is not released.
            try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            #expect(weakClient.isAlive)

            // And once the exchange ends, the client goes with it.
            sessionTask.seed()
            #expect(await weakClient.isReleased())
        }
    }

    /// The overload that streams a request body goes through `beginOperation()` too.
    @Test
    func execute_whenStreamingAndClientWasShutDown_throwsInsteadOfCreatingATaskOnTheInvalidatedSession()
        async throws
    {
        // Given
        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let url = try #require(URL(string: "https://127.0.0.1:1/"))

        #expect(try await client.shutdown())

        // When / Then
        await #expect(throws: Internals.URLSessionClient.ClientClosedError.self) {
            _ = try await client.execute(
                request: URLRequest(url: url),
                streaming: Internals.AsyncStream<Internals.Bytes>()
            )
        }
    }
}

private struct UnexpectedClient: Error {}

private struct NeverFollowingRedirectStrategy: Internals.RedirectStrategy {

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        .doNotFollow
    }
}

private struct WeakURLSessionClient {

    private weak var client: Internals.URLSessionClient?

    init(_ client: Internals.URLSessionClient) {
        self.client = client
    }

    var isAlive: Bool {
        client != nil
    }

    /// Polled: whatever releases the client last does not have to do it before the caller's own reference
    /// goes.
    func isReleased() async -> Bool {
        for _ in 0..<200 {
            if client == nil {
                return true
            }

            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }

        return false
    }
}

#endif
