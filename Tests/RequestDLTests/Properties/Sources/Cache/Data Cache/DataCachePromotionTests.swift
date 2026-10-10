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
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// An entry read from the disk tier is kept in the memory tier, so the next read of it does not
/// go to the disk again. After a launch the memory tier is empty and every entry starts there.
struct DataCachePromotionTests {

    private let memoryCapacity: Int64 = 1_024 * 1_024

    private func makeCache() -> (DataCache, String) {
        let dataCache = DataCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: 8 * 1_024 * 1_024,
            suiteName: UUID().uuidString
        )

        return (dataCache, "https://example.com/" + UUID().uuidString)
    }

    private func response(_ key: String, policy: DataCache.Policy.Set) -> CachedResponse {
        .init(
            response: .init(
                url: key,
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [],
                isKeepAlive: true
            ),
            policy: policy
        )
    }

    /// Writes `count` bytes under `key`, then empties the memory tier: what a new launch finds.
    private func store(
        _ count: Int,
        key: String,
        policy: DataCache.Policy.Set,
        in dataCache: DataCache
    ) async throws {
        var buffer = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: policy),
                contentLength: Int64(count)
            )
        )

        await buffer.writeBuffer(await Internals.DataBuffer(Data(repeating: 0x61, count: count)))
        await dataCache.finalizeWrite(buffer, contentLengthHint: Int64(count))

        dataCache.storage.withMemoryStorage { $0.removeAll() }
    }

    private func isInMemory(_ key: String, in dataCache: DataCache) async -> Bool {
        await dataCache.getCachedData(forKey: key, policy: .memory) != nil
    }

    @Test(arguments: [0, 1, 10_000])
    func getCachedData_whenTheEntryComesFromTheDisk_keepsItInMemory(_ count: Int) async throws {
        // Given
        let (dataCache, key) = makeCache()
        try await store(count, key: key, policy: [.memory, .disk], in: dataCache)
        #expect(await isInMemory(key, in: dataCache) == false)

        // When
        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: [.memory, .disk]))

        // Then: what was served is the whole body, and memory has it now.
        #expect(await cached.data == Data(repeating: 0x61, count: count))
        #expect(await isInMemory(key, in: dataCache))

        // And it no longer needs the disk.
        await dataCache.storage.diskStorage.removeAll()

        let again = try #require(await dataCache.getCachedData(forKey: key, policy: .memory))
        #expect(await again.data == Data(repeating: 0x61, count: count))
        #expect(again.response.url?.absoluteString == key)
    }

    @Test
    func getCachedData_whenAskedForTheDiskOnly_doesNotTouchMemory() async throws {
        let (dataCache, key) = makeCache()
        try await store(100, key: key, policy: [.memory, .disk], in: dataCache)

        #expect(await dataCache.getCachedData(forKey: key, policy: .disk) != nil)
        #expect(await isInMemory(key, in: dataCache) == false)
    }

    @Test
    func getCachedData_whenTheEntryWasStoredForTheDiskOnly_doesNotKeepItInMemory() async throws {
        let (dataCache, key) = makeCache()
        try await store(100, key: key, policy: .disk, in: dataCache)

        #expect(await dataCache.getCachedData(forKey: key, policy: [.memory, .disk]) != nil)
        #expect(await isInMemory(key, in: dataCache) == false)
    }

    @Test
    func getCachedData_whenTheEntryIsTooBigForItsShareOfMemory_staysOnTheDisk() async throws {
        // Given: a twentieth of 1 MiB is about 52 KB.
        let (dataCache, key) = makeCache()
        try await store(100_000, key: key, policy: [.memory, .disk], in: dataCache)

        // When
        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: [.memory, .disk]))

        // Then: still served whole, and still not in memory.
        #expect(await cached.data.count == 100_000)
        #expect(await isInMemory(key, in: dataCache) == false)
    }

    @Test
    func getCachedData_whenAskedAgainAfterItWasKept_isServedFromMemory() async throws {
        let (dataCache, key) = makeCache()
        try await store(1_000, key: key, policy: [.memory, .disk], in: dataCache)

        _ = await dataCache.getCachedData(forKey: key, policy: [.memory, .disk])
        await dataCache.storage.diskStorage.removeAll()

        // The disk is empty, so only memory can answer this.
        #expect(await dataCache.getCachedData(forKey: key, policy: [.memory, .disk]) != nil)
    }

    // MARK: - The cache changing under a read

    private func keyInStorage(_ key: String, in dataCache: DataCache) -> String {
        dataCache.base64EncodedKey(key)
    }

    private func finish(_ key: String, in dataCache: DataCache) -> Bool {
        let dataURL = Internals.ByteURL()
        dataURL.replace(with: [UInt8](repeating: 0x62, count: 10))

        return dataCache.storage.finishPromotion(
            key: key,
            cachedResponse: response(key, policy: [.memory, .disk]),
            dataURL: dataURL
        )
    }

    @Test
    func promotion_whenNothingChanged_isKept() {
        let (dataCache, key) = makeCache()
        let stored = keyInStorage(key, in: dataCache)

        #expect(dataCache.storage.beginPromotion(key: stored))
        #expect(finish(stored, in: dataCache))
        #expect(dataCache.storage.withMemoryStorage { $0.contains(stored) })
    }

    @Test
    func promotion_whenTheKeyIsRemovedMeanwhile_isNotKept() async {
        let (dataCache, key) = makeCache()
        let stored = keyInStorage(key, in: dataCache)

        #expect(dataCache.storage.beginPromotion(key: stored))
        await dataCache.remove(forKey: key)

        #expect(finish(stored, in: dataCache) == false)
        #expect(dataCache.storage.withMemoryStorage { $0.contains(stored) } == false)
    }

    @Test
    func promotion_whenEverythingIsRemovedMeanwhile_isNotKept() async {
        let (dataCache, key) = makeCache()
        let stored = keyInStorage(key, in: dataCache)

        #expect(dataCache.storage.beginPromotion(key: stored))
        await dataCache.removeAll()

        #expect(finish(stored, in: dataCache) == false)
    }

    @Test
    func promotion_whenTheKeyIsRevalidatedMeanwhile_isNotKept() async {
        let (dataCache, key) = makeCache()
        let stored = keyInStorage(key, in: dataCache)

        #expect(dataCache.storage.beginPromotion(key: stored))
        await dataCache.updateCached(key: key, cachedResponse: response(key, policy: [.memory, .disk]))

        #expect(finish(stored, in: dataCache) == false)
    }

    @Test
    func promotion_whenAWriteStartsMeanwhile_isNotKept() {
        let (dataCache, key) = makeCache()
        let stored = keyInStorage(key, in: dataCache)

        #expect(dataCache.storage.beginPromotion(key: stored))
        let token = dataCache.storage.beginWrite(key: stored)

        #expect(finish(stored, in: dataCache) == false)
        token.end()
    }

    @Test
    func beginPromotion_whenTheKeyIsBeingWrittenPromotedOrInMemory_doesNotStart() {
        let (dataCache, key) = makeCache()
        let stored = keyInStorage(key, in: dataCache)

        let token = dataCache.storage.beginWrite(key: stored)
        #expect(dataCache.storage.beginPromotion(key: stored) == false)
        token.end()

        #expect(dataCache.storage.beginPromotion(key: stored))
        #expect(dataCache.storage.beginPromotion(key: stored) == false)
        dataCache.storage.cancelPromotion(key: stored)

        #expect(dataCache.storage.beginPromotion(key: stored))
        #expect(finish(stored, in: dataCache))
        #expect(dataCache.storage.beginPromotion(key: stored) == false)
    }
}
