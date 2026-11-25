//
// See LICENSE for this package's licensing information.
//

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
import struct Foundation.URL
import struct Foundation.UUID
#endif

/// How long an entry is kept: what `useCachedDataOnly` serves, the lifetime a response that
/// declares none is given, and what a `304` leaves of the freshness an entry already had.
struct CacheFreshnessTests {

    /// Answers the conditional request with `head`.
    private final class Client: RequestExecutingClient, @unchecked Sendable {

        let head: Internals.ResponseHead?

        private let lock = SwiftAsyncStream.Lock()
        private var _revalidations = 0

        /// How many conditional requests were asked of the network.
        var revalidations: Int {
            lock.withLock { _revalidations }
        }

        init(head: Internals.ResponseHead? = nil) {
            self.head = head
        }

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
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
            lock.withLock { _revalidations += 1 }

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

    private func makeConfiguration(strategy: CacheStrategy) -> RequestConfiguration {
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com/" + UUID().uuidString
        configuration.cachePolicy = .all
        configuration.cacheStrategy = strategy
        return configuration
    }

    private func head(status: UInt = 200, _ headers: [(String, String)]) -> Internals.ResponseHead {
        .init(
            url: "https://example.com",
            status: .init(code: status, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    private func response(
        _ headers: [(String, String)],
        status: UInt = 200,
        age seconds: Double = 0
    ) -> CachedResponse {
        CachedResponse(response: head(status: status, headers), policy: .all, date: Date().addingTimeInterval(-seconds))
    }

    private func store(_ cachedResponse: CachedResponse, key: String, in dataCache: DataCache) async {
        await dataCache.setCachedData(
            CachedData(cachedResponse: cachedResponse, buffer: await Internals.DataBuffer(Data("body".utf8))),
            forKey: key
        )
    }

    private func decide(
        _ configuration: RequestConfiguration,
        in dataCache: DataCache,
        client: Client = Client()
    ) async -> Internals.CacheControl.Output {
        await Internals.CacheControl(requestConfiguration: configuration, dataCache: dataCache, logger: nil)(client)
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

    /// Whether the answer is the error `useCachedDataOnly` gives when there is nothing to serve.
    private func isEmptyCachedDataError(_ output: Internals.CacheControl.Output) async -> Bool {
        guard case .task(let task) = output else {
            return false
        }

        do {
            for try await _ in task.response {}
        } catch {
            return error is EmptyCachedDataError
        }

        return false
    }

    /// The body `output` serves, or `nil` when it serves nothing or fails.
    private func servedBody(_ output: Internals.CacheControl.Output) async -> Data? {
        guard case .task(let task) = output else {
            return nil
        }

        var body = Data()

        do {
            for try await step in task.response {
                if case .download(let download) = step {
                    for try await chunk in download.bytes {
                        body.append(contentsOf: chunk)
                    }
                }
            }
        } catch {
            return nil
        }

        return body
    }

    private func httpDate(_ offset: Double) -> String {
        Date().addingTimeInterval(offset).toHTTPDateString()
    }

    private func isStored(_ key: String, in dataCache: DataCache) async -> Bool {
        await dataCache.getCachedData(forKey: key, policy: .all) != nil
    }

    // MARK: - useCachedDataOnly

    @Test
    func useCachedDataOnly_whenTheEntryIsStale_servesItAndKeepsIt() async throws {
        // Given: an entry that passed its `max-age`.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .useCachedDataOnly)
        await store(response([("Cache-Control", "max-age=60")], age: 120), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then: the caller asked for what is stored, and gets it, and it is still there for the
        // next time the network is not.
        #expect(isServed(output))
        #expect(await isEmptyCachedDataError(output) == false)
        #expect(await isStored(configuration.url, in: dataCache))
    }

    /// Offline: the network is not asked for anything, however old the entry is, and each tier
    /// still has it afterwards.
    @Test(arguments: [DataCache.Policy.Set.memory, .disk, .all], [60.0, 86_400.0 * 365])
    func useCachedDataOnly_whenTheEntryIsStale_servesItFromEachTierWithoutTheNetworkAndKeepsItThere(
        policy: DataCache.Policy.Set,
        age: Double
    ) async throws {
        // Given: an entry well past its `max-age`, stored in `policy`'s tiers.
        let dataCache = makeCache()
        var configuration = makeConfiguration(strategy: .useCachedDataOnly)
        configuration.cachePolicy = policy

        await dataCache.setCachedData(
            CachedData(
                cachedResponse: CachedResponse(
                    response: head([("Cache-Control", "max-age=1"), ("ETag", "\"v1\"")]),
                    policy: policy,
                    date: Date().addingTimeInterval(-age)
                ),
                buffer: await Internals.DataBuffer(Data("body".utf8))
            ),
            forKey: configuration.url
        )

        // When
        let client = Client()
        let output = await decide(configuration, in: dataCache, client: client)

        // Then: given as stored, without a request, not even to validate it.
        #expect(await servedBody(output) == Data("body".utf8))
        #expect(client.revalidations == 0)

        // And: still in every tier it was written to, so the next call finds it too.
        for tier in [DataCache.Policy.Set.memory, .disk] where policy.contains(tier) {
            #expect(await dataCache.getCachedData(forKey: configuration.url, policy: tier) != nil)
        }

        let again = await decide(configuration, in: dataCache, client: client)

        #expect(await servedBody(again) == Data("body".utf8))
    }

    /// What is removed is an entry that cannot be read, however recent: not one that is old.
    @Test
    func useCachedDataOnly_whenTheBodyDoesNotMatchTheResponse_removesTheEntry() async throws {
        // Given: an entry that says its body is 4 bytes longer than what is stored.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .useCachedDataOnly)
        await store(response([("Content-Length", "8")]), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then
        #expect(await isEmptyCachedDataError(output))
        #expect(await isStored(configuration.url, in: dataCache) == false)
    }

    @Test(arguments: ["must-revalidate", "no-cache"])
    func useCachedDataOnly_whenTheStaleEntryMustBeRevalidated_isAnErrorAndStaysStored(_ directive: String) async throws
    {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .useCachedDataOnly)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "max-age=60, \(directive)")], age: 120),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(configuration, in: dataCache)

        // Then: it cannot be given stale, and is not thrown away for a request that can validate it.
        #expect(await isEmptyCachedDataError(output))
        #expect(await isStored(configuration.url, in: dataCache))
    }

    @Test
    func useCachedDataOnly_whenTheMustRevalidateEntryIsFresh_servesIt() async throws {
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .useCachedDataOnly)
        await store(
            response([("Cache-Control", "max-age=3600, must-revalidate")], age: 10),
            key: configuration.url,
            in: dataCache
        )

        let output = await decide(configuration, in: dataCache)

        #expect(isServed(output))
        #expect(await isEmptyCachedDataError(output) == false)
    }

    @Test
    func useCachedDataOnly_whenThereIsNothingStored_isAnError() async throws {
        let output = await decide(makeConfiguration(strategy: .useCachedDataOnly), in: makeCache())

        #expect(await isEmptyCachedDataError(output))
    }

    @Test
    func returnCachedDataElseLoad_whenTheEntryIsStale_loadsAndLeavesItForWhoeverAsksForStoredData() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)
        await store(response([("Cache-Control", "max-age=60")], age: 120), key: configuration.url, in: dataCache)

        // When
        let output = await decide(configuration, in: dataCache)

        // Then: it is not served here, and not removed either: a load that then fails (offline) is
        // followed by a request for what is stored.
        #expect(isServed(output) == false)
        #expect(await isStored(configuration.url, in: dataCache))
    }

    // MARK: - An entry that declares no freshness

    @Test
    func freshness_whenNothingSaysHowLong_andTheEntryIsAYearOld_isNotServed() async throws {
        // Given: a validator and a `Last-Modified`, and a year since it was stored.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("ETag", "\"v1\""), ("Last-Modified", "Mon, 01 Jan 2024 00:00:00 GMT")], age: 86_400 * 365),
            key: configuration.url,
            in: dataCache
        )

        // Then
        #expect(isServed(await decide(configuration, in: dataCache)) == false)
    }

    @Test
    func freshness_whenNothingSaysHowLong_andThereIsNoLastModified_isNotServed() async throws {
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)
        await store(response([("ETag", "\"v1\"")], age: 1), key: configuration.url, in: dataCache)

        #expect(isServed(await decide(configuration, in: dataCache)) == false)
    }

    @Test(arguments: [
        // (seconds the resource had gone unchanged when it was served, Age, seconds since stored, served)
        (1_000.0, 0.0, 50.0, true),
        (1_000.0, 0.0, 200.0, false),
        (1_000.0, 90.0, 20.0, false),
        // A tenth of ten days is a day, which is also the ceiling.
        (864_000.0, 0.0, 3_600.0, true),
        (864_000.0, 0.0, 90_000.0, false),
        // A tenth of a hundred days is ten, cut to a day.
        (8_640_000.0, 0.0, 3_600.0, true),
        (8_640_000.0, 0.0, 90_000.0, false),
        // Changed at the moment it was served, or after.
        (0.0, 0.0, 0.0, false),
        (-60.0, 0.0, 0.0, false),
    ])
    func freshness_whenNothingSaysHowLong_isATenthOfTheTimeSinceItChanged_atMostADay(
        _ unchanged: Double,
        _ age: Double,
        _ sinceStored: Double,
        _ isFresh: Bool
    ) async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)
        let generated = Date().addingTimeInterval(-sinceStored)

        var headers = [
            ("Last-Modified", generated.addingTimeInterval(-unchanged).toHTTPDateString()),
            ("Date", generated.toHTTPDateString()),
        ]

        if age > 0 {
            headers.append(("Age", String(Int(age))))
        }

        await store(response(headers, age: sinceStored), key: configuration.url, in: dataCache)

        // Then
        #expect(isServed(await decide(configuration, in: dataCache)) == isFresh)
    }

    @Test
    func freshness_whenThereIsAMaxAge_theEstimateIsNotUsed() async throws {
        // Given: changed a year before it was served, but a `max-age` of a minute, a minute ago.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response(
                [
                    ("Cache-Control", "max-age=30"),
                    ("Last-Modified", httpDate(-86_400 * 365)),
                    ("Date", httpDate(-60)),
                ],
                age: 60
            ),
            key: configuration.url,
            in: dataCache
        )

        #expect(isServed(await decide(configuration, in: dataCache)) == false)
    }

    // MARK: - Errors

    @Test
    func freshness_whenAnErrorDeclaresNoLifetime_isNotServedEvenWithLastModified() async throws {
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        await store(
            response([("Last-Modified", httpDate(-86_400 * 365)), ("Date", httpDate(-60))], status: 404, age: 60),
            key: configuration.url,
            in: dataCache
        )

        #expect(isServed(await decide(configuration, in: dataCache)) == false)
    }

    @Test
    func freshness_whenAnErrorDeclaresALifetime_isServedWithinIt() async throws {
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)
        await store(
            response([("Cache-Control", "max-age=3600")], status: 404, age: 60),
            key: configuration.url,
            in: dataCache
        )

        #expect(isServed(await decide(configuration, in: dataCache)))
    }

    @Test(arguments: [
        (UInt(404), [("Last-Modified", "Mon, 01 Jan 2024 00:00:00 GMT")], false),
        (UInt(405), [], false),
        (UInt(410), [("ETag", "\"v1\"")], false),
        (UInt(414), [], false),
        (UInt(501), [], false),
        (UInt(404), [("Cache-Control", "max-age=3600")], true),
        (UInt(410), [("Cache-Control", "public, max-age=60")], true),
        (UInt(404), [("Cache-Control", "max-age=0")], false),
        (UInt(200), [], true),
        (UInt(301), [], true),
    ])
    func store_whenTheResponseIsAnError_isKeptOnlyWithALifetimeOfItsOwn(
        _ status: UInt,
        _ headers: [(String, String)],
        _ isKept: Bool
    ) async throws {
        // Given: nothing stored, so the request goes out and the cache is offered the response.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .returnCachedDataElseLoad)

        guard case .cache(let writer, _) = await decide(configuration, in: dataCache) else {
            Issue.record("Nothing was stored, so the request should go out")
            return
        }

        // When
        let stream = writer?(head(status: status, headers))
        stream?.close()
        await dataCache.waitUntilIdle()

        // Then
        #expect((stream != nil) == isKept)
    }

    // MARK: - What a 304 does to an entry

    @Test
    func revalidation_whenA304SaysNothingOfFreshness_theEntryKeepsItsMaxAge() async throws {
        // Given: an entry whose `max-age` ran out.
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "public, max-age=3600")], age: 7_200),
            key: configuration.url,
            in: dataCache
        )

        // When: the origin confirms it with a `Cache-Control` that has no `max-age`.
        let confirmed = await decide(
            configuration,
            in: dataCache,
            client: Client(head: head(status: 304, [("Cache-Control", "private")]))
        )

        // Then: the entry is served, now with the new directive and the lifetime it had.
        #expect(isServed(confirmed))

        let stored = try #require(await dataCache.getCachedData(forKey: configuration.url, policy: .all))
        let cacheControl = stored.response.headers["Cache-Control"]?.joined(separator: ",") ?? ""
        #expect(cacheControl.contains("private"))
        #expect(cacheControl.contains("max-age=3600"))
        #expect(!cacheControl.contains("public"))

        // And: it is fresh for the next request, without asking the origin again.
        var again = configuration
        again.cacheStrategy = .returnCachedDataElseLoad
        #expect(sources(await decide(again, in: dataCache)) == [.cache])
    }

    @Test
    func revalidation_whenA304SaysNoStore_isNeitherKeptNorUsed() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "max-age=3600")], age: 7_200),
            key: configuration.url,
            in: dataCache
        )

        // When
        let output = await decide(
            configuration,
            in: dataCache,
            client: Client(head: head(status: 304, [("Cache-Control", "no-store")]))
        )

        // Then: the request goes out, and what was stored is gone.
        #expect(isServed(output) == false)
        #expect(await isStored(configuration.url, in: dataCache) == false)
    }

    @Test
    func revalidation_whenA304SaysNoCache_isUsedOnceAndRevalidatedEveryTimeAfter() async throws {
        // Given
        let dataCache = makeCache()
        let configuration = makeConfiguration(strategy: .reloadAndValidateCachedData)

        await store(
            response([("ETag", "\"v1\""), ("Cache-Control", "max-age=3600")], age: 7_200),
            key: configuration.url,
            in: dataCache
        )

        // When
        let confirmed = await decide(
            configuration,
            in: dataCache,
            client: Client(head: head(status: 304, [("Cache-Control", "no-cache")]))
        )

        // Then: it answers the request that validated it.
        #expect(sources(confirmed) == [.revalidation, .cache])

        // And: nothing is served from it without a validation, whatever `max-age` it had.
        var again = configuration
        again.cacheStrategy = .returnCachedDataElseLoad
        #expect(isServed(await decide(again, in: dataCache)) == false)
        #expect(await isStored(configuration.url, in: dataCache))
    }
}
