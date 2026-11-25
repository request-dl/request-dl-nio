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
import struct Foundation.Date
import struct Foundation.URL
#endif

/// Writing a key again leaves the previous write of it behind unless something takes it away, and
/// what is left behind comes back: it is what the directory scan finds once the newer one is gone.
struct DataCacheGenerationsTests {

    private func response(_ etag: String, date: Date) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://example.com/a",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [.init(name: "ETag", value: etag)],
                isKeepAlive: true
            ),
            policy: .disk,
            date: date
        )
    }

    private func etag(of cached: CachedData?) -> String? {
        cached?.cachedResponse.response.headers.first { $0.name == "ETag" }?.value
    }

    private func cachedDirectories(in directory: URL) async throws -> [String] {
        try await Internals.directoryEntryNames(atPath: directory.filePath.string)
            .filter { $0.hasSuffix(".cached") }
    }

    private func write(
        _ etag: String,
        date: Date,
        body: Int,
        to cache: DataCache,
        key: String
    ) async {
        await cache.setCachedData(
            CachedData(
                cachedResponse: response(etag, date: date),
                buffer: await Internals.DataBuffer(Data(repeating: 1, count: body))
            ),
            forKey: key
        )
    }

    @Test
    func rewritingAKey_leavesOnlyTheNewestGeneration() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a key written, then written again.
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 50_000_000
            let key = "https://example.com/a"

            await write("\"v1\"", date: Date().addingTimeInterval(-100), body: 5_000, to: cache, key: key)
            await write("\"v2\"", date: Date(), body: 5_000, to: cache, key: key)
            await cache.waitUntilIdle()

            // Then: the first write is not kept next to the second.
            let directories = try await cachedDirectories(in: directoryURL)
            #expect(directories.count == 1)
            #expect(etag(of: await cache.getCachedData(forKey: key, policy: .disk)) == "\"v2\"")
        }
    }

    @Test
    func removeForKey_afterTheKeyWasRewritten_doesNotBringTheOlderWriteBack() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a key written twice, on a storage that looks again on every miss.
            let storage = DiskStorage(directory: directoryURL, missRescanInterval: 0)
            let key = "k1"

            for (etag, age) in [("\"v1\"", 100.0), ("\"v2\"", 0.0)] {
                var (buffer, _, recordURL) = await storage.allocateBuffer(
                    key: key,
                    cachedResponse: response(etag, date: Date().addingTimeInterval(-age)),
                    contentLength: 0,
                    maximumCapacity: .max
                )
                await buffer?.writeData(Data([0x1]))
                try? await buffer?.close()
                #expect(recordURL != nil)
            }

            // When: it is removed.
            await storage.remove(key)

            // Then: nothing of it is left to be found, now or on the next look.
            #expect(await storage[key] == nil)
            let directories = try await cachedDirectories(in: directoryURL)
            #expect(directories.isEmpty)
        }
    }

    @Test
    func aFailedRewrite_keepsThePreviousGeneration() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry, and a refresh of it that starts writing and then fails.
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 50_000_000
            let key = "https://example.com/a"

            await write("\"v1\"", date: Date().addingTimeInterval(-100), body: 5_000, to: cache, key: key)

            var buffer = try #require(
                await cache.allocateBuffer(
                    key: key,
                    cachedResponse: response("\"v2\"", date: Date()),
                    contentLength: 0
                )
            )
            await buffer.writeData(Data(repeating: 2, count: 10))

            // When
            await cache.discardFailedWrite(buffer, forKey: key)

            // Then: the entry that was there is still there, and it is the only one.
            #expect(etag(of: await cache.getCachedData(forKey: key, policy: .disk)) == "\"v1\"")
            let directories = try await cachedDirectories(in: directoryURL)
            #expect(directories.count == 1)
        }
    }
}
