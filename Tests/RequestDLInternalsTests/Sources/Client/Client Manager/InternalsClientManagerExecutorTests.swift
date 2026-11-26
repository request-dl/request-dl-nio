//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation

/// `Internals.ClientManager.resolvedClient(provider:sessionConfiguration:)` actually selects and
/// caches an `Internals.URLSessionClient` for a configuration `resolveExecutor()` picks
/// `.urlSession` for, rather than that decision staying abstract.
///
/// Distinct from `RequestConfigurationURLSessionClientTests` (`RequestDLTests`), which
/// forces `.urlSession` by hand-building `Internals.URLSessionClient` directly and bypasses
/// `Internals.ClientManager` entirely: these tests are the ones that would fail if
/// `resolvedClient` merely inspected `resolveExecutor()` without ever building/caching a real
/// client behind it.
///
/// Only the `.urlSession` half of the suite: none of these tests reference `.nio` or
/// `NIOTransportServices`, so they need nothing beyond `canImport(Darwin)` and keep compiling
/// under `--disable-default-traits`. The `.nio`/`.nioTransportServices` half lives in
/// `InternalsClientManagerExecutorTests+NIO.swift`, which needs `NIOCore` to exist at all.
struct InternalsClientManagerExecutorTests {

    @Test
    func resolvedClient_whenConfigurationHasNoExecutorPreference_actuallyRunsOverURLSession() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // `resolveExecutor()` alone only says what *could* run. The point of this suite is
        // confirming `resolvedClient` actually built and cached the client that decision points
        // to, not just returned a matching enum case with nothing behind it.
        #expect(sessionConfiguration.resolveExecutor() == .urlSession)

        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))

        // When
        let resolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        guard case .urlSession(let client) = resolved else {
            Issue.record("Expected .urlSession, got \(resolved)")
            return
        }

        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(result.head.status.code == 200)
        #expect(decoded.response == output)
    }

    @Test
    func resolvedClient_whenCalledTwice_reusesTheSameURLSessionClient() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        let first = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        let second = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        guard
            case .urlSession(let firstClient) = first,
            case .urlSession(let secondClient) = second
        else {
            Issue.record("Expected both resolutions to be .urlSession")
            return
        }

        #expect(firstClient === secondClient)
    }

    /// The client is told what the session's decompression announces, which is what its conditional
    /// revalidation request carries (`revalidationHead`), so the server answers it for the same
    /// representation as the request it revalidates.
    @Test(
        arguments: [
            (Internals.Decompression.disabled, "identity" as String?),
            (.enabled(algorithms: [ManagerTestAlgorithm()], limit: .none), "x-requestdl-manager-test"),
            (.enabled(algorithms: [ManagerTestAlgorithm(isNative: true)], limit: .none), nil),
        ]
    )
    func resolvedClient_givesTheClientTheAcceptEncodingTheSessionAnnounces(
        _ decompression: Internals.Decompression,
        _ expected: String?
    ) async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        var sessionConfiguration = Internals.Session.Configuration()
        sessionConfiguration.decompression = decompression

        // When
        let resolved = try await manager.resolvedClient(
            provider: Internals.SharedSessionProvider(),
            sessionConfiguration: sessionConfiguration
        )

        // Then
        guard case .urlSession(let client) = resolved else {
            Issue.record("Expected .urlSession, got \(resolved)")
            return
        }

        #expect(client.acceptEncoding == expected)
    }

    /// A `.urlSession` client resolved once and used for two sequential calls on the very same
    /// instance (what `Internals.CacheControl`'s conditional revalidation does: a `HEAD`, then,
    /// if still needed, the real `GET`) must not be invalidated in the gap between the two just
    /// because its pooled entry has gone stale and an eviction pass happens to run there. Evicting
    /// only un-pools: the caller's own reference is what keeps the client, and its session, alive
    /// for the second call.
    ///
    /// Exercises `_evictIfNeeded(protecting:)` directly, with the entry's `readAt` backdated by
    /// hand, so it is the first thing an eviction reaches for: real background-sweep timing can't
    /// be pinned to a test-sized window without either a multi-minute wait or shrinking `lifetime`
    /// enough to risk flaking on a loaded CI runner.
    @Test
    func resolvedClient_whenEvictedBetweenTwoCallsOnTheSameClient_stillServesTheSecondCall() async throws {
        // Given: a real client, resolved and used once, plus a second, decoy entry that never ran
        // anything at all.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000, maximumCount: 1)
        let provider = Internals.SharedSessionProvider()
        let heldConfiguration = Internals.Session.Configuration()

        var decoyConfiguration = Internals.Session.Configuration()
        decoyConfiguration.timeout.connect = 90_000_000_000

        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello"), at: uri)
        defer { localServer.cleanup(at: uri) }
        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))

        let heldResolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: heldConfiguration
        )
        let decoyResolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: decoyConfiguration
        )

        guard
            case .urlSession(let heldClient) = heldResolved,
            case .urlSession = decoyResolved
        else {
            Issue.record("Expected both resolutions to be .urlSession")
            return
        }

        // The `HEAD` of the revalidation, so to speak.
        let first = try await heldClient.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )
        #expect(first.head.status.code == 200)

        // When: the held entry is the oldest one in a table over its ceiling, so the eviction
        // that follows takes it out.
        let heldIdentifier = ObjectIdentifier(heldClient)

        manager.tableLock.withLock {
            for key in manager._table.keys {
                guard let items = manager._table[key] else { continue }

                manager._table[key] = items.map { item in
                    Internals.ClientManager.Item(
                        sessionConfiguration: item.sessionConfiguration,
                        client: item.client,
                        readAt: item.client.objectIdentifier == heldIdentifier ? 0 : 1,
                        lastKnownOperationGeneration: item.client.operationGeneration
                    )
                }
            }

            manager._evictIfNeeded()
        }

        let survivingClients = manager._table.values.flatMap { $0 }.map(\.client.objectIdentifier)
        #expect(!survivingClients.contains(heldIdentifier))

        // Then: the `GET`.
        let second = try await heldClient.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        #expect(second.head.status.code == 200)
    }
}

// MARK: - Unpooled and unmatched clients

extension InternalsClientManagerExecutorTests {

    /// `Internals.RedirectConfiguration.==` answers `false` for `.strategy` against everything, itself
    /// included, so such an entry could never be handed back to anyone. It would only sit in the table, with
    /// its whole `URLSession`, until the sweep got to it, five minutes later, while every following lookup
    /// walked a table that kept growing. So it is neither searched for nor stored, as with `.nio`: the
    /// caller owns the client and the client invalidates its session once nothing refers to it.
    @Test
    func resolvedClient_whenConfigurationCarriesARedirectStrategy_shouldNotBeReusedNorTracked() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Self.redirectStrategyConfiguration()

        // When
        var clients = [Internals.URLSessionClient]()

        for _ in 0..<250 {
            let resolved = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )

            guard case .urlSession(let client) = resolved else {
                Issue.record("Expected .urlSession, got \(resolved)")
                return
            }

            clients.append(client)
        }

        // Then
        #expect(Set(clients.map(ObjectIdentifier.init)).count == clients.count)
        #expect(manager.count == 0)
    }

    /// Nothing but the caller keeps an untracked client alive, and its session is only ever invalidated
    /// by the client itself, so the client has to be released once the caller lets go of it.
    @Test
    func resolvedClient_whenConfigurationCarriesARedirectStrategy_shouldReleaseTheClientOnceDropped() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Self.redirectStrategyConfiguration()

        // When
        let weakClient = try await {
            let resolved = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )

            guard case .urlSession(let client) = resolved else {
                throw UnexpectedClient()
            }

            return WeakURLSessionClient(client)
        }()

        // Then
        #expect(await weakClient.isReleased())
    }

    /// The reason an untracked client cannot simply be invalidated when the caller drops it: the response
    /// outlives that reference. Here the caller keeps nothing but the `SessionTask`, and the body still has to
    /// arrive.
    @Test
    func resolvedClient_whenCallerDropsAnUntrackedClientMidResponse_shouldStillDeliverTheBody() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Self.redirectStrategyConfiguration()

        // When: the resolved client is out of scope as soon as the response has started.
        let sessionTask = try await {
            let resolved = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )

            guard case .urlSession(let client) = resolved else {
                throw UnexpectedClient()
            }

            return try await client.execute(
                request: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData),
                readingMode: .length(1_024),
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                delegate: AcceptAnyServerTrustDelegate()
            )
        }()

        var receivedBytes = 0

        for try await step in sessionTask.response {
            if case .download(let downloadStep) = step {
                for try await chunk in downloadStep.bytes {
                    receivedBytes += chunk.count
                }
            }
        }

        // Then
        #expect(receivedBytes >= output.utf8.count)
    }

    /// The table was bounded for `.nio` and not for `.urlSession`: an entry that can never be matched again
    /// (a `SecureConnection` hook is compared by identity, so one created per request never is) was only
    /// evictable once it was five minutes old, so a burst of requests grew the table past its ceiling and
    /// every insert after that sorted all of it under the global lock.
    @Test
    func resolvedClient_whenConfigurationsNeverMatch_shouldNotGrowPastMaximumCount() async throws {
        // Given
        let maximumCount = 8
        let manager = Internals.ClientManager(
            lifetime: 5 * 60 * 1_000_000_000,
            maximumCount: maximumCount
        )
        let provider = Internals.SharedSessionProvider()

        // When: a new hook instance every time, as a caller who builds one per request does.
        for _ in 0..<(maximumCount * 4) {
            var secureConnection = Internals.SecureConnection()
            secureConnection.trustDecisionObserver = NoopTrustDecisionObserver()

            var sessionConfiguration = Internals.Session.Configuration()
            sessionConfiguration.requiredExecutor = .urlSession
            sessionConfiguration.secureConnection = secureConnection

            _ = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }

        // Then
        #expect(manager.count <= maximumCount)
    }

    /// The ceiling only ever un-pools a `.urlSession` client; whoever was handed it a moment ago and has not
    /// started using it yet keeps it alive, and it must still work, not have been invalidated behind them.
    @Test
    func resolvedClient_whenEvictingAnIdleClientSomeoneStillHolds_shouldKeepItUsable() async throws {
        // Given: a client resolved but not yet used, the oldest entry in the table.
        let maximumCount = 2
        let manager = Internals.ClientManager(
            lifetime: 5 * 60 * 1_000_000_000,
            maximumCount: maximumCount
        )
        let provider = Internals.SharedSessionProvider()

        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello"), at: uri)
        defer { localServer.cleanup(at: uri) }
        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))

        let held = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: Internals.Session.Configuration()
        )

        guard case .urlSession(let heldClient) = held else {
            Issue.record("Expected .urlSession, got \(held)")
            return
        }

        // When: enough other configurations arrive to push it out of the table.
        for index in 0..<(maximumCount * 3) {
            var sessionConfiguration = Internals.Session.Configuration()
            sessionConfiguration.timeout.connect = Int64(1_000_000_000 + index)

            _ = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }

        #expect(manager.count <= maximumCount)

        // Then
        let result = try await heldClient.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        #expect(result.head.status.code == 200)
    }

    /// The same configuration still reuses its client, which is the whole point of the table.
    @Test
    func resolvedClient_whenConfigurationCanBePooled_shouldStillBeTracked() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        var sessionConfiguration = Internals.Session.Configuration()
        sessionConfiguration.requiredExecutor = .urlSession

        // When
        for _ in 0..<10 {
            _ = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }

        // Then
        #expect(manager.count == 1)
    }

    /// Making a client without a `secureConnection` reads no file, so it does not queue for the file
    /// system's thread pool: a pool kept full by disk writes would otherwise hold every request of a
    /// session that is never pooled (one with an `onRedirect`) just to have a `URLSession` made.
    @Test
    func resolvedClient_whenNotPoolableAndWithoutTLS_doesNotWaitForTheFileSystemPool() async throws {
        // Given: every thread of the pool busy, and more work than it has threads for behind them.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Self.redirectStrategyConfiguration()
        let gate = DispatchSemaphore(value: 0)
        let blockers = max(16, ProcessInfo.processInfo.activeProcessorCount * 4) + 8

        for _ in 0..<blockers {
            _Concurrency.Task {
                try? await Internals.FileSystemManager.run { gate.wait() }
            }
        }

        defer {
            for _ in 0..<blockers {
                gate.signal()
            }
        }

        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        // When / Then
        let isURLSession = try await completing(within: 30) {
            let resolved = try await manager.resolvedClient(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )

            if case .urlSession = resolved {
                return true
            }

            return false
        }

        #expect(isURLSession)
    }

    // MARK: - Private static methods

    private static func redirectStrategyConfiguration() -> Internals.Session.Configuration {
        var sessionConfiguration = Internals.Session.Configuration()
        sessionConfiguration.requiredExecutor = .urlSession
        sessionConfiguration.redirectConfiguration = .strategy(FollowingRedirectStrategy())
        return sessionConfiguration
    }
}

private struct UnexpectedClient: Error {}

private struct FollowingRedirectStrategy: Internals.RedirectStrategy {

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        .follow(context.redirectRequest)
    }
}

private final class NoopTrustDecisionObserver: TrustDecisionObserver, @unchecked Sendable {

    func callAsFunction(_ decision: TrustDecision) {}
}

private struct WeakURLSessionClient {

    private weak var client: Internals.URLSessionClient?

    init(_ client: Internals.URLSessionClient) {
        self.client = client
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

/// Test-only stand-in for the real TLS challenge handling; see the identical delegate in
/// `InternalsURLSessionClientTests`/`RequestConfigurationURLSessionClientTests` for why this
/// exists at all: `LocalServer` is always TLS-terminated with a throwaway self-signed
/// certificate.
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

/// A custom algorithm (or, with `isNative`, one CFNetwork decodes on its own), for what a client
/// is told to announce.
private struct ManagerTestAlgorithm: Internals.DecompressionAlgorithm {

    struct Stream: Internals.DecompressorStream {
        mutating func callAsFunction(decompressing bytes: Data) throws -> Data { bytes }
        mutating func finish() throws -> Data { Data() }
    }

    var isNative = false

    var contentEncodingValue: String { isNative ? "gzip" : "x-requestdl-manager-test" }
    var isNativelyDecodedByURLSession: Bool { isNative }

    func callAsFunction() throws -> any Internals.DecompressorStream { Stream() }
}

#endif
