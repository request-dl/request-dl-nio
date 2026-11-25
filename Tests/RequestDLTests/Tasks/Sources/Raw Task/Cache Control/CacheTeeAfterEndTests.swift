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
import struct Foundation.UUID
#endif

/// A tee that reaches a download after it ended (the review's B4) must not leave its writer
/// waiting, holding the key's write token.
struct CacheTeeAfterEndTests {

    private struct DownloadFailure: Error {}

    private func response(_ etag: String) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://example.com",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [.init(name: "ETag", value: etag)],
                isKeepAlive: true
            ),
            policy: .all
        )
    }

    /// Runs `write` against `stream` the way the cache task does, and says how it ended, or that
    /// it was still waiting after `seconds`.
    private func outcome(
        of stream: Internals.AsyncStream<Internals.Chunk>,
        into buffer: DataCache.Buffer,
        within seconds: Double = 5
    ) async -> String {
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                var buffer = buffer

                do {
                    try await Internals.CacheControl.write(stream, to: &buffer)
                    return "finished"
                } catch {
                    return String(describing: type(of: error))
                }
            }

            group.addTask {
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return "still waiting"
            }

            let first = await group.next() ?? "nothing"
            group.cancelAll()
            stream.close()

            return first
        }
    }

    @Test(arguments: [true, false])
    func aTeeAttachedAfterTheDownloadEnded_endsItsWriter_andTheEntryItWasReplacingStays(failed: Bool) async throws {
        // Given: an entry, and a refresh of it whose download is over (failed, or closed) by the time the
        // tee is attached.
        let cache = DataCache(memoryCapacity: 8_000_000, diskCapacity: 8_000_000, suiteName: UUID().uuidString)
        let key = "https://example.com/" + UUID().uuidString

        await cache.setCachedData(
            CachedData(cachedResponse: response("\"v1\""), buffer: await Internals.DataBuffer(Data("old".utf8))),
            forKey: key
        )

        let buffer = try #require(
            await cache.allocateBuffer(key: key, cachedResponse: response("\"v2\""), contentLength: 0)
        )
        #expect(cache.storage.isWriting(key: cache.base64EncodedKey(key)))

        let download = await Internals.DownloadBuffer(readingMode: .passthrough)

        if failed {
            download.failed(DownloadFailure())
        } else {
            download.close()
        }

        await download.waitUntilIdle()

        let stream = Internals.DownloadBuffer.makeCacheStream()
        download.cacheStream(stream)
        await download.waitUntilIdle()

        // When
        let result = await outcome(of: stream, into: buffer)

        // Then: the writer was told, rather than waiting for a body that was never coming.
        #expect(result == String(describing: Internals.CacheStreamAfterEndError.self))

        // And when it discards what it began, the key is free again and the old entry is served.
        await cache.discardFailedWrite(buffer, forKey: key)

        #expect(cache.storage.isWriting(key: cache.base64EncodedKey(key)) == false)

        let cached = try #require(await cache.getCachedData(forKey: key, policy: .all))
        #expect(await cached.data == Data("old".utf8))
    }
}
