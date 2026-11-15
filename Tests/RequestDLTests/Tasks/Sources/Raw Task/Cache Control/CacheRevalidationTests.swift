//
// See LICENSE for this package's licensing information.
//

import Logging
@_spi(Testing) import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.UUID
#endif

/// What `Internals.CacheControl` does with an entry that is stale, or that is being revalidated:
/// whether the freshness a response declares is read the way RFC 9111 says, and what the
/// conditional request confirms, and for whom.
///
/// These go through `Internals.CacheControl` with a client that answers the conditional request
/// itself, so each one decides the entry from what it was given and nothing else: no server, no
/// sleeping past a `max-age`, and a revalidation that can be held half way.
struct CacheRevalidationTests {

    /// Opened once, and stays open: a wait that comes after it does not block.
    private actor Gate {

        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else {
                return
            }

            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters {
                waiter.resume()
            }

            waiters = []
        }
    }

    /// Answers the conditional request with `head`, after `onRequest` has run (and, with it, after
    /// whatever the test does at that point), and counts them.
    private final class Client: RequestExecutingClient, @unchecked Sendable {

        let head: Internals.ResponseHead?
        let onRequest: (@Sendable () async -> Void)?

        var requests: Int {
            lock.withLock { _requests }
        }

        private let lock = SwiftAsyncStream.Lock()
        private var _requests = 0

        init(head: Internals.ResponseHead?, onRequest: (@Sendable () async -> Void)? = nil) {
            self.head = head
            self.onRequest = onRequest
        }

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            fatalError("These only look at what is decided before a request goes out")
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?,
            metrics: Internals.RequestMetricsCollector?
        ) async throws -> Internals.ResponseHead {
            lock.withLock { _requests += 1 }
            await onRequest?()

            // What each executor records for the conditional request it sends.
            let now = Date()

            metrics?.append(
                Internals.TransactionMetrics(
                    source: .revalidation,
                    url: nil,
                    fetchStart: now,
                    responseStart: now,
                    responseEnd: now
                )
            )

            guard let head else {
                throw Internals.TaskCancelledError()
            }

            return head
        }
    }

    // MARK: - Fixtures

    private func makeCache() -> DataCache {
        DataCache(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 8 * 1_024 * 1_024,
            suiteName: UUID().uuidString
        )
    }

    private func makeConfiguration(
        strategy: CacheStrategy,
        policy: DataCache.Policy.Set = .all,
        headers: [(String, String)] = []
    ) -> RequestConfiguration {
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com/" + UUID().uuidString
        configuration.cachePolicy = policy
        configuration.cacheStrategy = strategy

        for (name, value) in headers {
            configuration.headers.add(name: name, value: value)
        }

        return configuration
    }

    private func response(
        _ headers: [(String, String)],
        status: UInt = 200,
        varyRequestHeaders: [String: String]? = nil,
        policy: DataCache.Policy.Set = .all,
        age seconds: Double = 0
    ) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://example.com",
                status: .init(code: status, reason: ""),
                version: .init(minor: 1, major: 1),
                headers: headers.map { .init(name: $0.0, value: $0.1) },
                isKeepAlive: true
            ),
            policy: policy,
            varyRequestHeaders: varyRequestHeaders,
            date: Date().addingTimeInterval(-seconds)
        )
    }

    private func store(
        _ cachedResponse: CachedResponse,
        body: String = "body",
        key: String,
        in dataCache: DataCache
    ) async {
        await dataCache.setCachedData(
            CachedData(cachedResponse: cachedResponse, buffer: await Internals.DataBuffer(Data(body.utf8))),
            forKey: key
        )
    }

    private func head(status: UInt, _ headers: [(String, String)]) -> Internals.ResponseHead {
        .init(
            url: "https://example.com",
            status: .init(code: status, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    private func decide(
        _ configuration: RequestConfiguration,
        in dataCache: DataCache,
        client: Client = Client(head: nil)
    ) async -> Internals.CacheControl.Output {
        await Internals.CacheControl(
            requestConfiguration: configuration,
            dataCache: dataCache,
            logger: nil
        )(client)
    }

    private func isServed(_ output: Internals.CacheControl.Output) -> Bool {
        if case .task = output {
            return true
        }

        return false
    }

    private func sources(_ output: Internals.CacheControl.Output) -> [Internals.TransactionMetrics.Source]? {
        guard case .task(let task) = output else {
            return nil
        }

        return task.metrics?.transactions().map(\.source)
    }

    private func httpDate(_ offset: Double) -> String {
        Date().addingTimeInterval(offset).toHTTPDateString()
    }

    // MARK: - A 304 renews the entry, whether or not it repeats the headers

    @Test
    func revalidation_whenA304RepeatsTheSameCacheControl_servesTheEntryInsteadOfGoingToTheNetwork() async throws {
        // Given: a stale entry (stored two hours ago with a `max-age` of one hour), and a server
        // that answers the conditional request with a 304 that says the same thing again.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)
        let headers = [("ETag", "\"v1\""), ("Cache-Control", "public, max-age=3600")]

        await store(response(headers, age: 7_200), key: configuration.url, in: dataCache)

        let client = Client(head: head(status: 304, [("Cache-Control", "public, max-age=3600")]))

        // When
        let output = await decide(configuration, in: dataCache, client: client)

        // Then: it is the cached entry, after the revalidation and nothing else (RFC 9111 §4.3.4).
        #expect(sources(output) == [.revalidation, .cache])
        #expect(client.requests == 1)
    }

    @Test
    func revalidation_whenA304RepeatsTheSameCacheControl_theEntryIsFreshAfterwards() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)
        let headers = [("ETag", "\"v1\""), ("Cache-Control", "public, max-age=3600")]

        await store(response(headers, age: 7_200), key: configuration.url, in: dataCache)

        let client = Client(head: head(status: 304, [("Cache-Control", "public, max-age=3600")]))
        _ = await decide(configuration, in: dataCache, client: client)

        // When: the next request takes what is stored without asking the origin again.
        var again = configuration
        again.cacheStrategy = .returnCachedDataElseLoad
        let reused = await decide(again, in: dataCache, client: client)

        #expect(sources(reused) == [.cache])
        #expect(client.requests == 1)
    }

    @Test
    func revalidation_whenA304CarriesNoCacheControlAtAll_stillRenewsTheEntry() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "public, max-age=3600")], age: 7_200),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache, client: Client(head: head(status: 304, [])))

        // Then
        #expect(sources(output) == [.revalidation, .cache])
    }

    // MARK: - Freshness that is there but cannot be read is stale

    @Test(arguments: ["0", "-1", "", "yesterday", "Sun 06 Nov 1994"])
    func freshness_whenExpiresIsNotADate_isStale(_ expires: String) async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(response([("Expires", expires)]), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then: not served, and the request goes out.
        #expect(isServed(output) == false)
    }

    @Test
    func freshness_whenExpiresIsInTheFuture_isStillServed() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(response([("Expires", httpDate(3_600))]), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output))
    }

    @Test
    func freshness_whenTwoExpiresDisagree_theEarlierOneWins() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Expires", httpDate(-60)), ("Expires", httpDate(3_600))]),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output) == false)
    }

    @Test(arguments: ["max-age=abc", "max-age=-1", "max-age=", "max-age", "max-age=1.5", "max-age=1e3"])
    func freshness_whenMaxAgeIsNotANumberOfSeconds_isStale(_ directive: String) async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(response([("Cache-Control", "public, " + directive)]), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output) == false)
    }

    @Test
    func freshness_whenTwoMaxAgesDisagree_theSmallerOneWins() async throws {
        // Given: stored ten seconds ago, so `max-age=5` has run out and `max-age=3600` has not.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Cache-Control", "max-age=3600"), ("Cache-Control", "max-age=5")], age: 10),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output) == false)
    }

    @Test
    func freshness_whenMaxAgeIsBeyondWhatAnIntHolds_isStillAValidMaxAge() async throws {
        // Given: RFC 9111 §1.2.2 reads it as 2^31 seconds, which is not a malformed header.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Cache-Control", "max-age=99999999999999999999")]),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output))
    }

    @Test
    func freshness_whenMaxAgeIsQuoted_isRead() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(response([("Cache-Control", "max-age=\"3600\"")]), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output))
    }

    // MARK: - Age

    @Test
    func freshness_whenAgeUsesUpTheMaxAge_isStale() async throws {
        // Given: a response that was already 3500 s old when it arrived, and a `max-age` of 3600
        // that is counted from when it was made, not from when it arrived. 100 s left; 200 s
        // have gone by since it was stored.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Cache-Control", "max-age=3600"), ("Age", "3500")], age: 200),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output) == false)
    }

    @Test
    func freshness_whenAgeLeavesRoomInTheMaxAge_isStillServed() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Cache-Control", "max-age=3600"), ("Age", "3500")], age: 10),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output))
    }

    @Test
    func freshness_whenAgeIsNotANumber_countsAsNone() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Cache-Control", "max-age=3600"), ("Age", "old")]),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(isServed(output))
    }

    @Test
    func revalidation_whenA304ComesWithoutAge_theEntryDoesNotKeepTheOldOne() async throws {
        // Given: an entry that arrived through a cache that had held it for 3500 s, and has since
        // run out; revalidating confirms it, and the origin says nothing of an age.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "max-age=3600"), ("Age", "3500")], age: 200),
            key: configuration.url,
            in: dataCache
        )

        let client = Client(head: head(status: 304, [("Cache-Control", "max-age=3600")]))

        // When
        let output = await decide(configuration, in: dataCache, client: client)

        // Then: it is fresh for as long as the origin said, and the old age is not held against it.
        #expect(sources(output) == [.revalidation, .cache])

        let stored = await dataCache.getCachedData(forKey: configuration.url, policy: .all)
        #expect(stored?.response.headers["Age"] == nil)
    }

    // MARK: - A revalidation does not touch an entry written meanwhile

    /// `DataCache` keys an entry by URL, so another account's request for the same URL replaces
    /// the entry while the first is waiting for the origin's answer. What the origin confirmed is
    /// the first account's entry, which is no longer there.
    @Test(arguments: [DataCache.Policy.Set.memory, .disk, .all])
    func revalidation_whenAnotherAccountStoresTheKeyMeanwhile_doesNotGiveItTheFirstAccountsResponse(
        _ policy: DataCache.Policy.Set
    ) async throws {
        // Given: an entry stored for user1, and user1 revalidating it.
        let dataCache = makeCache()
        let configuration = makeConfiguration(
            strategy: .reloadAndValidateCachedData,
            policy: policy,
            headers: [("Authorization", "Bearer user1")]
        )

        let credentials = { (token: String) -> [String: String] in
            [
                "authorization": Internals.CacheControl.digest(ofCredential: token, field: "authorization"),
                "cookie": "",
                "proxy-authorization": "",
            ]
        }

        let headers = [("ETag", "\"v1\""), ("Cache-Control", "max-age=3600")]

        await store(
            response(headers, varyRequestHeaders: credentials("Bearer user1"), policy: policy),
            body: "user1's body",
            key: configuration.url,
            in: dataCache
        )

        let started = Gate()
        let release = Gate()

        let client = Client(
            // The 304 carries a different `Cache-Control`, so the stored response has to change.
            head: head(status: 304, [("Cache-Control", "max-age=7200")]),
            onRequest: {
                await started.open()
                await release.wait()
            }
        )

        let revalidation = _Concurrency.Task {
            await decide(configuration, in: dataCache, client: client)
        }

        await started.wait()

        // When: user2 misses on credentials and stores the key while the origin has not answered.
        await store(
            response(headers, varyRequestHeaders: credentials("Bearer user2"), policy: policy),
            body: "user2's body",
            key: configuration.url,
            in: dataCache
        )

        await release.open()
        let output = await revalidation.value

        // Then: user1 is not given what is stored for user2: the request goes out instead.
        #expect(isServed(output) == false)

        // And what is stored is still user2's, with user2's digests.
        let stored = try #require(await dataCache.getCachedData(forKey: configuration.url, policy: policy))
        #expect(await stored.data == Data("user2's body".utf8))
        #expect(stored.cachedResponse.varyRequestHeaders == credentials("Bearer user2"))
        #expect(stored.response.headers.first(name: "Cache-Control") == "max-age=3600")
    }

    @Test(arguments: [DataCache.Policy.Set.memory, .disk, .all])
    func revalidation_whenNothingIsStoredMeanwhile_stillRenewsTheEntry(_ policy: DataCache.Policy.Set) async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData, policy: policy)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "max-age=5")], policy: policy, age: 10),
            body: "the body",
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(
            configuration,
            in: dataCache,
            client: Client(head: head(status: 304, [("Cache-Control", "max-age=7200")]))
        )

        // Then
        #expect(sources(output) == [.revalidation, .cache])

        let stored = try #require(await dataCache.getCachedData(forKey: configuration.url, policy: policy))
        #expect(await stored.data == Data("the body".utf8))
        #expect(stored.response.headers.first(name: "Cache-Control") == "max-age=7200")
    }
}
