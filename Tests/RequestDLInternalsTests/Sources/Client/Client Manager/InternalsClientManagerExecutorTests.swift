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

    /// Regression coverage: a `.urlSession` client resolved once and used for two sequential
    /// calls on the very same instance -- exactly what `Internals.CacheControl`'s conditional
    /// revalidation does (a `HEAD`, then, if still needed, the real `GET`) -- must not be
    /// invalidated in the gap between the two just because its pooled entry's `readAt` (set once,
    /// at checkout) has gone stale by the time an eviction pass happens to run. An operation
    /// completing on the client (the `HEAD` above) is itself evidence of recent use that
    /// `Internals.ClientOperationQueue.generation`/`Internals.ClientManager.Item
    /// .lastKnownOperationGeneration` exist to capture.
    ///
    /// Exercises `_evictIfNeeded(protecting:)` directly, with both the protected entry's and a
    /// decoy entry's `readAt` backdated by hand: real background-sweep timing can't be pinned to
    /// a test-sized window without either a multi-minute wait or shrinking `lifetime` enough to
    /// risk flaking on a loaded CI runner, and the eviction path shares the exact same
    /// generation-vs-`lastKnownOperationGeneration` check the periodic sweep does.
    @Test
    func resolvedClient_whenOperationCompletesBetweenTwoCallsOnTheSameClient_survivesEvictionDespiteStaleReadAt()
        async throws
    {
        // Given: a real client, resolved and used once -- advancing its
        // `operationGeneration` past what the table recorded when it was checked out -- plus a
        // second, decoy entry that never ran anything at all.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000, maximumCount: 1)
        let provider = Internals.SharedSessionProvider()
        let protectedConfiguration = Internals.Session.Configuration()

        var decoyConfiguration = Internals.Session.Configuration()
        decoyConfiguration.timeout.connect = 90_000_000_000

        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello"), at: uri)
        defer { localServer.cleanup(at: uri) }
        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))

        let protectedResolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: protectedConfiguration
        )
        let decoyResolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: decoyConfiguration
        )

        guard
            case .urlSession(let protectedClient) = protectedResolved,
            case .urlSession = decoyResolved
        else {
            Issue.record("Expected both resolutions to be .urlSession")
            return
        }

        // A real request, run to completion on `protectedClient` -- mirrors the revalidation
        // `HEAD` finishing just before the real `GET` would start on the same client.
        _ = try await protectedClient.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )
        #expect(!protectedClient.isRunning)
        #expect(protectedClient.operationGeneration > .zero)

        // When: both entries' bookkeeping is backdated to look idle-and-expired, as a real
        // multi-minute-old checkout would -- except `protectedClient`'s recorded
        // `lastKnownOperationGeneration` (0, from its original checkout) purposefully still
        // doesn't match its *current* `operationGeneration`, since the request above ran after
        // that checkout. `protected` sorts older than `decoy` so an unfixed eviction, which
        // ignores this mismatch, deterministically picks it first.
        let protectedIdentifier = ObjectIdentifier(protectedClient)

        manager.tableLock.withLock {
            // Both configurations share one provider, and `_table` keys by provider identity
            // alone -- distinct `sessionConfiguration`s live as separate `Item`s in the *same*
            // key's array (see `_reusableItem`'s own per-item `sessionConfiguration` comparison)
            // -- so every item in every array needs backdating, not just each key's first.
            for key in manager._table.keys {
                guard let items = manager._table[key] else { continue }

                manager._table[key] = items.map { item in
                    let isProtected = item.client.objectIdentifier == protectedIdentifier

                    return Internals.ClientManager.Item(
                        sessionConfiguration: item.sessionConfiguration,
                        client: item.client,
                        readAt: isProtected ? 0 : 1,
                        lastKnownOperationGeneration: isProtected ? .zero : item.client.operationGeneration
                    )
                }
            }

            let evicted = manager._evictIfNeeded()

            // Then: only the decoy was evicted (and is what needs an explicit shutdown, since
            // `.urlSession` doesn't retire on release); the protected entry, despite its
            // even-more-expired `readAt`, is still in the table.
            #expect(evicted.count == 1)
            #expect(evicted.first?.objectIdentifier != protectedIdentifier)
        }

        let survivingClients = manager._table.values.flatMap { $0 }.map(\.client.objectIdentifier)
        #expect(survivingClients == [ObjectIdentifier(protectedClient)])
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

#endif
