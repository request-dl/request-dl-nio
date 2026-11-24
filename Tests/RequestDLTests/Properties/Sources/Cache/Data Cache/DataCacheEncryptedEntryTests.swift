//
// See LICENSE for this package's licensing information.
//

import Crypto
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

struct DataCacheEncryptedEntryTests {

    private func response(key: String, headers: [(String, String)] = []) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: key,
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: headers.map { .init(name: $0.0, value: $0.1) },
                isKeepAlive: true
            ),
            policy: .disk
        )
    }

    // MARK: - An empty body

    @Test
    func anEncryptedEntryWithAnEmptyBody_isReadWithoutWaitingForContentThatIsNotComing() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an empty body, sealed (its only chunk is the final one).
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            cache.encryptionKey = .init(Data(repeating: 0x02, count: 32))
            let key = "https://example.com/empty"

            let buffer = try #require(
                await cache.allocateBuffer(
                    key: key,
                    cachedResponse: response(key: key, headers: [("Transfer-Encoding", "chunked")]),
                    contentLength: 0
                )
            )
            await cache.finalizeWrite(buffer, contentLengthHint: 0)

            // Warms what is not about the body: the directory lookup, the file system pool.
            _ = await cache.getCachedData(forKey: key, policy: .disk)

            // When
            let clock = ContinuousClock()
            let start = clock.now
            let cached = await cache.getCachedData(forKey: key, policy: .disk)
            let elapsed = start.duration(to: clock.now)

            // Then: it is a hit, and nothing waited. Reopening a file that reads as empty used to
            // retry for ~290 ms, in case the empty answer was a stat that missed.
            #expect(cached != nil)
            #expect(cached?.buffer.readableBytes == 0)
            #expect(elapsed < .milliseconds(200))
        }
    }

    // MARK: - A key of any size

    @Test(arguments: [1, 10, 15, 17, 31, 33, 64])
    func aKeyThatIsNotAnAesSize_stillEncryptsTheEntry(size: Int) async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a key whose length AES does not take as it is.
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            cache.encryptionKey = .init(Data(repeating: 0x07, count: size))
            let key = "https://example.com/a"
            let body = Data("a body that must not show up on disk".utf8)

            // When
            await cache.setCachedData(
                CachedData(cachedResponse: response(key: key), buffer: await Internals.DataBuffer(body)),
                forKey: key
            )

            // Then: it was stored, comes back, and is not the plaintext on disk.
            let cached = try #require(await cache.getCachedData(forKey: key, policy: .disk))
            #expect(await cached.data == body)

            let raw = try await Self.contents(of: directoryURL)
            #expect(!Self.contains(raw, body))
        }
    }

    /// Every record file under `directory`, one after another.
    private static func contents(of directory: URL) async throws -> [UInt8] {
        var all: [UInt8] = []

        for name in try await Internals.directoryEntryNames(atPath: directory.filePath.string) {
            let record = directory.appendingPathComponent(name)

            for file in ["data.record", "response.record"] {
                let buffer = await Internals.FileBuffer(record.appendingPathComponent(file))
                all += await buffer.getBytes() ?? []
            }
        }

        return all
    }

    private static func contains(_ haystack: [UInt8], _ data: Data) -> Bool {
        let needle = Array(data)

        guard !needle.isEmpty, haystack.count >= needle.count else {
            return needle.isEmpty
        }

        for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }

        return false
    }
}
