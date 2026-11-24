//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

import class Foundation.FileManager

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
#endif

/// A body written in the clear has nothing in it that says it ended, so a write that was killed
/// halfway looked like a whole entry to whoever opened the directory next.
struct DiskStorageUnfinishedRecordTests {

    private func chunkedResponse(key: String) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://www.apple.com/\(key)",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [.init(name: "Transfer-Encoding", value: "chunked")],
                isKeepAlive: true
            ),
            policy: .disk
        )
    }

    /// A write that got as far as its first chunk, from a process that is then gone.
    private func startedWrite(
        in directoryURL: URL,
        key: String = "k1",
        bytes: Int = 1_000
    ) async throws -> URL {
        let storage = DiskStorage(directory: directoryURL, missRescanInterval: 0)

        var (buffer, _, recordURL) = await storage.allocateBuffer(
            key: key,
            cachedResponse: chunkedResponse(key: key),
            contentLength: 0,
            maximumCapacity: .max
        )

        await buffer?.writeData(Data(repeating: 0x1, count: bytes))
        try? await buffer?.close()

        return try #require(recordURL)
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.filePath.string)
    }

    // MARK: - Reading

    @Test
    func aWriteThatNeverFinished_isAMissAfterARestart() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a plaintext write that was killed after its first chunk.
            _ = try await startedWrite(in: directoryURL)

            // When: the next launch opens the same directory.
            let restarted = DiskStorage(directory: directoryURL, missRescanInterval: 0)

            // Then: the part of the body that arrived is not served as the response.
            #expect(await restarted["k1"] == nil)
        }
    }

    @Test
    func aFinishedWrite_isServedAfterARestart() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry written through the cache, to the end.
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            let key = "https://example.com/a"

            await cache.setCachedData(
                CachedData(
                    cachedResponse: chunkedResponse(key: "a"),
                    buffer: await Internals.DataBuffer(Data(repeating: 0x1, count: 1_000))
                ),
                forKey: key
            )

            // When: the next launch opens the same directory.
            let restarted = DiskStorage(directory: directoryURL, missRescanInterval: 0)
            let found = await restarted[cache.base64EncodedKey(key)]

            // Then: it is there, whole.
            #expect(found?.buffer.readableBytes == 1_000)
        }
    }

    @Test
    func anOlderFinishedGeneration_isServedWhileANewerOneIsUnfinished() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry, and a refresh of it that was killed after its first chunk.
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            let key = "https://example.com/a"
            let storageKey = cache.base64EncodedKey(key)

            await cache.setCachedData(
                CachedData(
                    cachedResponse: CachedResponse(
                        response: chunkedResponse(key: "a").response,
                        policy: .disk,
                        date: Date().addingTimeInterval(-100)
                    ),
                    buffer: await Internals.DataBuffer(Data(repeating: 0x1, count: 300))
                ),
                forKey: key
            )

            _ = try await startedWrite(in: directoryURL, key: storageKey, bytes: 50)

            // When
            let restarted = DiskStorage(directory: directoryURL, missRescanInterval: 0)
            let found = await restarted[storageKey]

            // Then: what was complete is what is served.
            #expect(found?.buffer.readableBytes == 300)
        }
    }

    // MARK: - Cleaning up

    @Test
    func anUnfinishedWriteLeftForLongerThanTheOrphanAge_isRemoved() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a write cut short, whose files nobody has touched for an hour.
            let recordURL = try await startedWrite(in: directoryURL)
            let longAgo = Date().addingTimeInterval(-3_600)

            for path in ["", "data.record", "response.record"] {
                try setModificationDate(longAgo, of: recordURL.appendingPathComponent(path))
            }

            // When: it is looked up.
            let restarted = DiskStorage(directory: directoryURL, missRescanInterval: 0)
            #expect(await restarted["k1"] == nil)

            // Then: it was taken for what it is, and cleaned up.
            #expect(await recordURL.isReachable == false)
        }
    }

    @Test
    func anUnfinishedWriteStillReceivingBytes_isNotRemoved() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a download that has been going on for an hour, whose directory was created
            // then but whose body file was written to a moment ago.
            let recordURL = try await startedWrite(in: directoryURL)
            let longAgo = Date().addingTimeInterval(-3_600)

            for path in ["", "response.record"] {
                try setModificationDate(longAgo, of: recordURL.appendingPathComponent(path))
            }

            // When: another process looks the key up.
            let reader = DiskStorage(directory: directoryURL, missRescanInterval: 0)
            #expect(await reader["k1"] == nil)

            // Then: the write that is still going on is left alone.
            #expect(await recordURL.isReachable)
        }
    }
}
