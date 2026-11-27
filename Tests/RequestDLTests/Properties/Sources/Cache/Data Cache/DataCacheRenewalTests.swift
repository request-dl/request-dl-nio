//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
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

/// What a revalidation, or a write that fails, leaves the other readers of the same entry.
struct DataCacheRenewalTests {

    private func response(
        _ etag: String,
        date: Date,
        policy: DataCache.Policy.Set,
        extraHeaders: [(String, String)] = []
    ) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://example.com",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: ([("ETag", etag), ("Cache-Control", "max-age=0")] + extraHeaders)
                    .map { .init(name: $0.0, value: $0.1) },
                isKeepAlive: true
            ),
            policy: policy,
            date: date
        )
    }

    private func store(
        _ cachedResponse: CachedResponse,
        body: Int = 1_000,
        key: String,
        in cache: DataCache
    ) async {
        await cache.setCachedData(
            CachedData(
                cachedResponse: cachedResponse,
                buffer: await Internals.DataBuffer(Data(repeating: 7, count: body))
            ),
            forKey: key
        )
    }

    private func etag(of cached: CachedData?) -> String? {
        cached?.cachedResponse.response.headers.first { $0.name == "ETag" }?.value
    }

    // MARK: - A renewal under a reader

    @Test
    func aReaderWhoseBodyWasMovedByARenewal_readsTheRenewedEntryAndLeavesItThere() async throws {
        // Given: an entry on disk that a reader has already looked up (its body not yet opened),
        // and a revalidation that then renews it, which moves the body to a new directory.
        let cache = DataCache(memoryCapacity: 0, diskCapacity: 8_000_000, suiteName: UUID().uuidString)

        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com/" + UUID().uuidString
        configuration.cachePolicy = .disk
        configuration.cacheStrategy = .returnCachedDataElseLoad

        let original = response("\"v1\"", date: Date().addingTimeInterval(-10), policy: .disk)
        await store(original, body: 100_000, key: configuration.url, in: cache)

        let cached = try #require(await cache.getCachedData(forKey: configuration.url, policy: .disk))

        let renewed = response("\"v1\"", date: Date(), policy: .disk)
        _ = await cache.renewCached(
            key: configuration.url,
            cachedResponse: renewed,
            expecting: original,
            policy: .disk
        )

        // When: the reader goes on to serve what it looked up.
        let control = Internals.CacheControl(requestConfiguration: configuration, dataCache: cache, logger: nil)

        let session = await control.makeCachedSession(
            cached,
            startedAt: Date(),
            revalidation: Internals.RequestMetricsCollector(),
            validated: true
        )

        // Then: it serves the renewed entry's body, and does not take the entry away.
        let served = try #require(session)
        var received = 0

        for try await step in served.response {
            if case .download(let download) = step {
                for try await chunk in download.bytes {
                    received += chunk.count
                }
            }
        }

        #expect(received == 100_000)

        let after = try #require(await cache.getCachedData(forKey: configuration.url, policy: .disk))
        #expect(after.cachedResponse.date == renewed.date)
    }

    @Test
    func removingAnEntryAsItWasRead_leavesOneThatWasRenewedSince() async throws {
        let cache = DataCache(memoryCapacity: 8_000_000, diskCapacity: 8_000_000, suiteName: UUID().uuidString)
        let key = "https://example.com/" + UUID().uuidString

        let original = response("\"v1\"", date: Date().addingTimeInterval(-10), policy: .all)
        await store(original, key: key, in: cache)

        let renewed = response("\"v1\"", date: Date(), policy: .all)
        _ = await cache.renewCached(key: key, cachedResponse: renewed, expecting: original, policy: .all)

        // When: whoever read the entry before the renewal asks for it to be removed.
        await cache.remove(forKey: key, ifDated: original.date)

        // Then
        #expect(await cache.getCachedData(forKey: key, policy: .all) != nil)

        // When: the one that is stored now is the one that was read.
        await cache.remove(forKey: key, ifDated: renewed.date)

        // Then
        #expect(await cache.getCachedData(forKey: key, policy: .all) == nil)
    }

    // MARK: - A write that fails

    @Test
    func aFailedWrite_keepsTheEntryInMemoryItWasGoingToReplace() async throws {
        // Given: an entry in memory, and a refresh of it that has begun and then fails.
        let cache = DataCache(memoryCapacity: 8_000_000, diskCapacity: 0, suiteName: UUID().uuidString)
        let key = "https://example.com/" + UUID().uuidString

        await store(response("\"v1\"", date: Date().addingTimeInterval(-100), policy: .memory), key: key, in: cache)

        var buffer = try #require(
            await cache.allocateBuffer(
                key: key,
                cachedResponse: response("\"v2\"", date: Date(), policy: .memory),
                contentLength: 0
            )
        )
        await buffer.writeData(Data(repeating: 2, count: 10))

        // When
        await cache.discardFailedWrite(buffer, forKey: key)

        // Then: the entry that was there is still served, with its own body.
        let cached = try #require(await cache.getCachedData(forKey: key, policy: .memory))
        #expect(etag(of: cached) == "\"v1\"")
        #expect(await cached.data == Data(repeating: 7, count: 1_000))
    }

    @Test
    func aFailedWrite_doesNotBringBackAnEntryThatAnotherWriteReplacedMeanwhile() async throws {
        let cache = DataCache(memoryCapacity: 8_000_000, diskCapacity: 0, suiteName: UUID().uuidString)
        let key = "https://example.com/" + UUID().uuidString

        await store(response("\"v1\"", date: Date().addingTimeInterval(-100), policy: .memory), key: key, in: cache)

        let failing = try #require(
            await cache.allocateBuffer(
                key: key,
                cachedResponse: response("\"v2\"", date: Date(), policy: .memory),
                contentLength: 0
            )
        )

        // A later write finishes while the first is still going on.
        await store(response("\"v3\"", date: Date(), policy: .memory), key: key, in: cache)

        // When
        await cache.discardFailedWrite(failing, forKey: key)
        failing.writeToken?.end()

        // Then
        let cached = try #require(await cache.getCachedData(forKey: key, policy: .memory))
        #expect(etag(of: cached) == "\"v3\"")
    }

    @Test
    func twoFailedWritesOfTheKey_theOlderFailingFirst_doNotBringBackTheBodyOfTheOlder() async throws {
        // Given: two writes of the same key going on at once, the second began while the first
        // had only part of its body.
        let cache = DataCache(memoryCapacity: 8_000_000, diskCapacity: 0, suiteName: UUID().uuidString)
        let key = "https://example.com/" + UUID().uuidString

        var first = try #require(
            await cache.allocateBuffer(
                key: key,
                cachedResponse: response("\"v1\"", date: Date(), policy: .memory),
                contentLength: 0
            )
        )
        await first.writeData(Data("PARTIAL-W1".utf8))

        var second = try #require(
            await cache.allocateBuffer(
                key: key,
                cachedResponse: response("\"v2\"", date: Date(), policy: .memory),
                contentLength: 0
            )
        )
        await second.writeData(Data("W2".utf8))

        // When: the older one fails first, then the other.
        await cache.discardFailedWrite(first, forKey: key)
        await cache.discardFailedWrite(second, forKey: key)

        // Then: nothing is served, and above all not the body that stopped half way.
        #expect(await cache.getCachedData(forKey: key, policy: .memory) == nil)
    }

    @Test
    func twoFailedWritesOfTheKey_neverLeaveAPartialBody_overAnEntryThatWasWhole() async throws {
        // Given: an entry, and two refreshes of it that go on at once.
        let cache = DataCache(memoryCapacity: 8_000_000, diskCapacity: 0, suiteName: UUID().uuidString)
        let key = "https://example.com/" + UUID().uuidString

        await store(response("\"v0\"", date: Date().addingTimeInterval(-100), policy: .memory), key: key, in: cache)

        var first = try #require(
            await cache.allocateBuffer(
                key: key,
                cachedResponse: response("\"v1\"", date: Date(), policy: .memory),
                contentLength: 0
            )
        )
        await first.writeData(Data("PARTIAL-W1".utf8))

        let second = try #require(
            await cache.allocateBuffer(
                key: key,
                cachedResponse: response("\"v2\"", date: Date(), policy: .memory),
                contentLength: 0
            )
        )

        // When
        await cache.discardFailedWrite(first, forKey: key)
        await cache.discardFailedWrite(second, forKey: key)

        // Then: what is served, if anything, is the whole entry from before, never the partial one.
        if let cached = await cache.getCachedData(forKey: key, policy: .memory) {
            #expect(etag(of: cached) == "\"v0\"")
            #expect(await cached.data == Data(repeating: 7, count: 1_000))
        }
    }

    // MARK: - The cost of a renewal

    @Test
    func renewingAnEntry_withRoomToSpare_doesNotMeasureTheDirectory() async throws {
        // Given: a cache with several entries, far from its capacity.
        let cache = DataCache(memoryCapacity: 0, diskCapacity: 8_000_000, suiteName: UUID().uuidString)
        var originals: [String: CachedResponse] = [:]

        for index in 0..<5 {
            let key = "https://example.com/\(UUID().uuidString)"
            let original = response("\"v\(index)\"", date: Date().addingTimeInterval(-10), policy: .disk)
            originals[key] = original
            await store(original, key: key, in: cache)
        }

        await cache.waitUntilIdle()
        let measuredBefore = cache.storage.diskStorage.measureCount

        // When: one of them is renewed.
        let (key, original) = try #require(originals.first)
        let renewed = response("\"v0\"", date: Date(), policy: .disk, extraHeaders: [("X-Pad", "a header")])
        let updated = await cache.renewCached(key: key, cachedResponse: renewed, expecting: original, policy: .disk)

        // Then: it was renewed, without a read and a stat of every entry.
        #expect(updated != nil)
        #expect(cache.storage.diskStorage.measureCount == measuredBefore)
    }
}

/// Room for a renewal is made at the expense of the other entries.
struct DiskStorageRenewalEvictionTests {

    private func response(_ key: String, date: Date, pad: Int = 0) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://example.com/\(key)",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [
                    .init(name: "ETag", value: "\"\(key)\""),
                    .init(name: "X-Pad", value: String(repeating: "a", count: pad)),
                ],
                isKeepAlive: true
            ),
            policy: .disk,
            date: date
        )
    }

    @Test
    func renewingTheLeastRecentlyUsedEntry_atCapacity_evictsAnotherOne() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: two entries that fill the cache, the one that is renewed being the older.
            let storage = DiskStorage(directory: directoryURL, missRescanInterval: 0)

            let first = response("k1", date: Date().addingTimeInterval(-100))
            let second = response("k2", date: Date().addingTimeInterval(-50))

            for (key, cachedResponse, body) in [("k1", first, 500), ("k2", second, 5_000)] {
                var (buffer, _, _) = await storage.allocateBuffer(
                    key: key,
                    cachedResponse: cachedResponse,
                    contentLength: 0,
                    maximumCapacity: .max
                )
                await buffer?.writeData(Data(repeating: 1, count: body))
                try? await buffer?.close()
            }

            let capacity = await storage.freeSpace(.max)

            // When: the older one is renewed with a response that is a little bigger, which
            // needs room that the cache does not have.
            let renewed = response("k1", date: Date(), pad: 300)

            await storage.updateCached(
                key: "k1",
                cachedResponse: renewed,
                expecting: first,
                maximumCapacity: capacity
            )

            // Then: what is renewed is not what makes room for itself.
            let found = await storage["k1"]
            #expect(found?.cachedResponse.date == renewed.date)
            #expect(await storage["k2"] == nil)
        }
    }
}
