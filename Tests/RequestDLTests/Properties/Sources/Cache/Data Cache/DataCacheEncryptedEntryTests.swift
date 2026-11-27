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

            // When
            let cached = await cache.getCachedData(forKey: key, policy: .disk)

            // Then: it is a hit, and nothing waited for content. Reopening a file that reads as
            // empty used to retry for ~290 ms, in case the empty answer was a stat that missed.
            #expect(cached != nil)
            #expect(cached?.buffer.readableBytes == 0)
            #expect(cache.storage.diskStorage.emptyContentWaits.value == 0)
        }
    }

    // MARK: - A key of any size

    @Test(arguments: [17, 31, 33, 40, 64])
    func aKeyThatIsNotAnAesSize_stillEncryptsTheEntry(size: Int) async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a key long enough, whose length AES does not take as it is.
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

    @Test(arguments: [0, 1, 8, 15])
    func aKeyShorterThanSixteenBytes_isRefused_andNothingIsWritten(size: Int) async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: a key too short to be one.
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            cache.encryptionKey = .init(Data(repeating: 0x07, count: size))
            let key = "https://example.com/a"
            let body = Data("a body that must not show up on disk".utf8)

            // When
            await cache.setCachedData(
                CachedData(
                    cachedResponse: response(key: key, headers: [("X-Secret", "s3cr3t")]),
                    buffer: await Internals.DataBuffer(body)
                ),
                forKey: key
            )

            // Then: the disk tier took nothing, and finds nothing.
            #expect(await cache.getCachedData(forKey: key, policy: .disk) == nil)
            let raw = try await Self.contents(of: directoryURL)
            #expect(raw.isEmpty)
        }
    }

    /// What anyone can do with a cache that was "encrypted" with an empty key (what a Keychain
    /// read that found nothing gives): derive the key from the constants of the package and the
    /// response record opens. Nothing may be on disk for that to work on.
    @Test
    func anEmptyKey_neverLeavesDataThatItsPublicKeyOpens() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            cache.encryptionKey = .init(Data())
            let key = "https://example.com/secret"
            let body = Data("a body that must not show up on disk".utf8)

            await cache.setCachedData(
                CachedData(
                    cachedResponse: response(key: key, headers: [("X-Secret", "s3cr3t")]),
                    buffer: await Internals.DataBuffer(body)
                ),
                forKey: key
            )

            // When: the key an attacker derives from public constants only.
            let publicKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: Data()),
                info: Data("request-dl.cache.encryption-key.v1".utf8),
                outputByteCount: 32
            )

            var opened: [Data] = []

            for name in try await Internals.directoryEntryNames(atPath: directoryURL.filePath.string) {
                let url = directoryURL.appendingPathComponent(name).appendingPathComponent("response.record")
                let raw = await Internals.FileBuffer(url).getBytes() ?? []

                if let box = try? AES.GCM.SealedBox(combined: Data(raw)),
                    let data = try? AES.GCM.open(
                        box,
                        using: publicKey,
                        authenticating: Data("request-dl.cache.response.v1\n\(key)".utf8)
                    )
                {
                    opened.append(data)
                }
            }

            // Then
            #expect(opened.isEmpty)
            let raw = try await Self.contents(of: directoryURL)
            #expect(raw.isEmpty)
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
