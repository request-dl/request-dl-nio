//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(NIOCore)

/// What the cache does with the response a redirect led to, the same on every executor.
///
/// The entry is keyed by the URL that was asked for. `/latest` answers `302 /v1` today and
/// `302 /v2` tomorrow: the body of `/v1`, stored under `/latest`, would be served for as long as it
/// is fresh without the redirect, which is what says which one it is, ever being seen again.
struct RedirectCacheTests {

    // MARK: - Private methods

    private func makeCache() async -> DataCache {
        let cache = DataCache(suiteName: UUID().uuidString)
        await cache.removeAll()
        cache.memoryCapacity = 8 * 1_024 * 1_024
        cache.diskCapacity = 8 * 1_024 * 1_024
        return cache
    }

    private func fetch(
        _ path: String,
        from server: ScriptedServer,
        cache: DataCache,
        executor: TransferTestExecutor
    ) async throws -> String {
        let data = try await completing(within: 30) {
            try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path(path)
                executor.pinnedSession
                    .cachePolicy(.all)
                    .cacheStrategy(.returnCachedDataElseLoad)
                    .cache(memoryCapacity: 0, diskCapacity: 0, url: cache.directoryURL)
            }
            .extractPayload()
            .result()
        }

        await cache.waitUntilIdle()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Tests

    /// The redirect moves between the two requests, and the second must see it: whatever the
    /// status, the response of the target is not the response of `/latest`.
    @Test(arguments: TransferTestExecutor.allCases, [301, 302, 303, 307, 308])
    func aResponseThatAnsweredARedirect_isNotStoredUnderTheURLThatRedirected(
        executor: TransferTestExecutor,
        status: Int
    ) async throws {
        // Given
        let moved = LockedValueBox<Bool>(false)

        let server = try await ScriptedServer { received in
            switch received.uri {
            case "/latest":
                return .redirect(status, to: moved.withLockedValue { $0 } ? "/v2" : "/v1")
            case "/v1":
                return .init(
                    status: 200,
                    headers: [("Cache-Control", "public, max-age=31536000, immutable")],
                    body: "v1"
                )
            default:
                return .init(
                    status: 200,
                    headers: [("Cache-Control", "public, max-age=31536000, immutable")],
                    body: "v2"
                )
            }
        }

        let cache = await makeCache()

        // When
        let first = try await fetch("/latest", from: server, cache: cache, executor: executor)
        moved.withLockedValue { $0 = true }
        let second = try await fetch("/latest", from: server, cache: cache, executor: executor)

        let wire = server.requests.map(\.uri)
        await server.shutdown()

        // Then
        #expect(first == "v1")
        #expect(second == "v2")
        #expect(wire == ["/latest", "/v1", "/latest", "/v2"])
    }

    /// What a redirect led to is stored when it is asked for directly, and then served: the
    /// target is a response of its own, and it stays one.
    @Test(arguments: TransferTestExecutor.allCases)
    func theTargetOfARedirect_whenAskedForDirectly_isStoredAndServed(executor: TransferTestExecutor) async throws {
        // Given
        let server = try await ScriptedServer { received in
            switch received.uri {
            case "/latest":
                return .redirect(302, to: "/v1")
            default:
                return .init(status: 200, headers: [("Cache-Control", "public, max-age=3600")], body: "v1")
            }
        }

        let cache = await makeCache()

        // When
        let viaRedirect = try await fetch("/latest", from: server, cache: cache, executor: executor)
        let direct = try await fetch("/v1", from: server, cache: cache, executor: executor)
        let directAgain = try await fetch("/v1", from: server, cache: cache, executor: executor)

        let wire = server.requests.map(\.uri)
        await server.shutdown()

        // Then: the one request of `/v1` that went out is the first direct one.
        #expect(viaRedirect == "v1")
        #expect(direct == "v1")
        #expect(directAgain == "v1")
        #expect(wire == ["/latest", "/v1", "/v1"])
    }

    /// A response that did not go through a redirect is stored as before.
    @Test(arguments: TransferTestExecutor.allCases)
    func aResponseThatWasNotRedirected_isStoredAndServed(executor: TransferTestExecutor) async throws {
        // Given
        let server = try await ScriptedServer { _ in
            .init(status: 200, headers: [("Cache-Control", "public, max-age=3600")], body: "plain")
        }

        let cache = await makeCache()

        // When
        let first = try await fetch("/plain", from: server, cache: cache, executor: executor)
        let second = try await fetch("/plain", from: server, cache: cache, executor: executor)

        let wire = server.requests.map(\.uri)
        await server.shutdown()

        // Then
        #expect(first == "plain")
        #expect(second == "plain")
        #expect(wire == ["/plain"])
    }

    // MARK: - The comparison

    private func head(url: String) -> Internals.ResponseHead {
        Internals.ResponseHead(
            url: url,
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: [],
            isKeepAlive: true
        )
    }

    @Test(arguments: [
        ("http://127.0.0.1:80/a", "http://127.0.0.1:80/a"),
        ("HTTP://Example.COM/a?x=1", "http://example.com/a?x=1"),
        ("http://example.com", "http://example.com/"),
        ("http://example.com/a#section", "http://example.com/a"),
        ("", "http://example.com/a"),
    ])
    func theSameURLInAnotherSpelling_isNotARedirect(answered: String, requested: String) {
        #expect(!Internals.CacheControl.isRedirected(head(url: answered), from: requested))
    }

    @Test(arguments: [
        ("http://example.com/b", "http://example.com/a"),
        ("http://example.com/docs/", "http://example.com/docs"),
        ("http://example.com/a?x=2", "http://example.com/a?x=1"),
        ("http://example.com:8080/a", "http://example.com/a"),
        ("https://example.com/a", "http://example.com/a"),
        ("http://other.com/a", "http://example.com/a"),
    ])
    func anotherURL_isARedirect(answered: String, requested: String) {
        #expect(Internals.CacheControl.isRedirected(head(url: answered), from: requested))
    }
}

#endif
