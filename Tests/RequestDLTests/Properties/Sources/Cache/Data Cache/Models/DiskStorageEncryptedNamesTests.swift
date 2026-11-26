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

/// With an encryption key, what a record directory is called must not say what was fetched.
struct DiskStorageEncryptedNamesTests {

    private static let secretURL = "https://api.example.com/v1/files?access_token=SECRET123&user=jane.doe"

    private static func key(_ byte: UInt8, size: Int = 32) -> DataCache.EncryptionKey {
        .init(Data(repeating: byte, count: size))
    }

    private static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func response(_ etag: String = "\"v1\"", date: Date = DiskStorageEncryptedNamesTests.date) -> CachedResponse
    {
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

    private func makeStorage(
        _ directory: URL,
        key: DataCache.EncryptionKey?,
        orphanAge: Double = 600
    ) -> DiskStorage {
        var storage = DiskStorage(directory: directory, missRescanInterval: 0, orphanAge: orphanAge)
        storage.encryptionKey = key
        return storage
    }

    /// A finished entry, written the way `DataCache` writes one.
    @discardableResult
    private func write(
        _ key: String,
        etag: String = "\"v1\"",
        date: Date = DiskStorageEncryptedNamesTests.date,
        body: Int = 100,
        to storage: DiskStorage
    ) async throws -> URL {
        var (buffer, _, recordURL) = await storage.allocateBuffer(
            key: key,
            cachedResponse: response(etag, date: date),
            contentLength: 0,
            maximumCapacity: .max
        )

        await buffer?.writeData(Data(repeating: 3, count: body))
        try await buffer?.close()

        let url = try #require(recordURL)
        await storage.finishRecord(at: url)
        return url
    }

    private func recordNames(in directory: URL) async throws -> [String] {
        try await Internals.directoryEntryNames(atPath: directory.filePath.string)
            .filter { $0.hasSuffix(".cached") }
    }

    /// Everything a name could be read as: each dot separated part, and that part decoded from
    /// base64url when it is one.
    private func readings(of name: String) -> [String] {
        name.split(separator: ".").flatMap { part -> [String] in
            var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

            while base64.count % 4 != 0 {
                base64 += "="
            }

            guard let data = Data(base64Encoded: base64) else {
                return [String(part)]
            }

            return [String(part), String(decoding: data, as: UTF8.self)]
        }
    }

    // MARK: - What the name says

    /// T8 of the review.
    @Test
    func anEncryptedEntry_isNotNamedAfterItsURL() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            let cache = DataCache(url: directoryURL)
            cache.diskCapacity = 1_000_000
            cache.encryptionKey = Self.key(2)

            // When
            await cache.setCachedData(
                CachedData(cachedResponse: response(), buffer: await Internals.DataBuffer(Data("hello".utf8))),
                forKey: Self.secretURL
            )

            // Then: nothing of the URL is in the name, however it is read.
            let names = try await recordNames(in: directoryURL)
            #expect(names.count == 1)

            let base64 = Data(Self.secretURL.utf8).base64EncodedString()

            for name in names {
                #expect(!name.contains(String(base64.prefix(20))))

                for reading in readings(of: name) {
                    for piece in ["SECRET123", "access_token", "api.example.com", "jane", "https", "files"] {
                        #expect(!reading.contains(piece))
                    }
                }
            }

            // And the entry is still found by its URL.
            let cached = try #require(await cache.getCachedData(forKey: Self.secretURL, policy: .disk))
            #expect(await cached.data == Data("hello".utf8))
        }
    }

    @Test
    func theSameURLAndKey_areNamedTheSame_andAnotherKeyIsNamedDifferently() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: the same entry written in three caches, twice with a key and once with another.
            var names: [String] = []

            for (index, key) in [Self.key(1), Self.key(1), Self.key(2)].enumerated() {
                let directory = directoryURL.appendingPathComponent("\(index)", isDirectory: true)
                try await write("k1", to: makeStorage(directory, key: key))
                names += try await self.recordNames(in: directory)
            }

            // Then: the name is what the URL and the key make of it, and nothing else.
            #expect(names.count == 3)
            #expect(names[0] == names[1])
            #expect(names[0] != names[2])
        }
    }

    @Test
    func aKeyOfAnotherSize_isNamedDifferentlyFromOneWithTheSameBytes() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            var names: Set<String> = []

            for (index, key) in [Self.key(1, size: 16), Self.key(1, size: 32), Self.key(1, size: 20)].enumerated() {
                let directory = directoryURL.appendingPathComponent("\(index)", isDirectory: true)
                try await write("k1", to: makeStorage(directory, key: key))
                names.formUnion(try await self.recordNames(in: directory))
            }

            #expect(names.count == 3)
        }
    }

    @Test
    func withoutAKey_theNameIsWhatItWas() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            let storage = makeStorage(directoryURL, key: nil)

            // When
            try await write("k1", to: storage)

            // Then: `<date>.<key>.cached`, as before.
            let bitPattern = String(Self.date.timeIntervalSinceReferenceDate.bitPattern, radix: 36)
            #expect(try await recordNames(in: directoryURL) == ["\(bitPattern).k1.cached"])
        }
    }

    // MARK: - Finding it again

    @Test
    func anEntry_isFoundAfterARestart_underTheSameKeyOnly() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            try await write("k1", to: makeStorage(directoryURL, key: Self.key(1)))

            // When / Then: a new process with the same key finds it, with another key or none it
            // is a miss.
            #expect(await makeStorage(directoryURL, key: Self.key(1))["k1"]?.cachedResponse.date == Self.date)
            #expect(await makeStorage(directoryURL, key: Self.key(2))["k1"] == nil)
            #expect(await makeStorage(directoryURL, key: nil)["k1"] == nil)
        }
    }

    @Test
    func removingAKey_removesEveryDirectoryOfIt_andOnlyIt() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: two entries, one of them with two generations (the older one unfinished).
            let storage = makeStorage(directoryURL, key: Self.key(1))
            try await write("k1", to: storage)
            try await write("k2", to: storage)

            var (buffer, _, _) = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: response("\"v2\"", date: Self.date.addingTimeInterval(10)),
                contentLength: 0,
                maximumCapacity: .max
            )
            await buffer?.writeData(Data(repeating: 1, count: 10))
            try await buffer?.close()

            // When
            await storage.remove("k1")

            // Then: the restart finds neither generation of it, and still finds the other.
            let restarted = self.makeStorage(directoryURL, key: Self.key(1))
            #expect(await restarted["k1"] == nil)
            #expect(await restarted["k2"] != nil)
            #expect(try await recordNames(in: directoryURL).count == 1)
        }
    }

    @Test
    func removingAllEntriesSince_goesByTheDateInTheName() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            let storage = makeStorage(directoryURL, key: Self.key(1))
            try await write("old", date: Self.date.addingTimeInterval(-100), to: storage)
            try await write("new", date: Self.date.addingTimeInterval(100), to: storage)

            // When
            await storage.removeAll(since: Self.date)

            // Then
            #expect(await storage["old"] == nil)
            #expect(await storage["new"] != nil)

            await storage.removeAll()
            #expect(try await recordNames(in: directoryURL).isEmpty)
        }
    }

    @Test
    func writingAKeyAgain_keepsOneGeneration_underTheNewNames() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            let storage = makeStorage(directoryURL, key: Self.key(1))

            // When: written twice, the second one newer.
            try await write("k1", etag: "\"v1\"", date: Self.date, to: storage)
            try await write("k1", etag: "\"v2\"", date: Self.date.addingTimeInterval(10), to: storage)

            // Then: the older directory went when the newer was finished, and removing the key
            // does not bring it back after a restart.
            #expect(try await recordNames(in: directoryURL).count == 1)

            await storage.remove("k1")

            #expect(await self.makeStorage(directoryURL, key: Self.key(1))["k1"] == nil)
        }
    }

    @Test
    func renewingAnEntry_keepsItUnderItsName() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            let storage = makeStorage(directoryURL, key: Self.key(1))
            let original = response("\"v1\"")
            try await write("k1", to: storage)

            // When
            let renewed = response("\"v1\"", date: Self.date.addingTimeInterval(50))
            await storage.updateCached(key: "k1", cachedResponse: renewed, expecting: original, maximumCapacity: .max)

            // Then: still one directory, which a restart reads, body included.
            #expect(try await recordNames(in: directoryURL).count == 1)

            let restarted = self.makeStorage(directoryURL, key: Self.key(1))
            let cached = try #require(await restarted["k1"])
            #expect(cached.cachedResponse.date == renewed.date)
            #expect(cached.buffer.readableBytes == 100)
        }
    }

    // MARK: - Names that cannot be read

    @Test
    func entriesOfAnotherKey_stillCountAndCanBeEvicted() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry written under a key that is no longer the one in use.
            try await write("k1", body: 5_000, to: makeStorage(directoryURL, key: Self.key(1)))
            let current = makeStorage(directoryURL, key: Self.key(2))

            // When: there is room for it, and then there is not.
            let usage = await current.freeSpace(.max)
            #expect(usage >= 5_000)
            #expect(try await recordNames(in: directoryURL).count == 1)

            await current.freeSpace(100)

            // Then
            #expect(try await recordNames(in: directoryURL).isEmpty)
        }
    }

    // MARK: - Names from before

    @Test(arguments: ["bGVnYWN5LXVybA", "sha256.0123456789abcdef"])
    func anEntryWithTheOldName_isAMissWithAKey_andIsSweptOnceItIsInUse(legacyKey: String) async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry written before names were hidden, whose name is its key in the clear.
            try await write(legacyKey, to: makeStorage(directoryURL, key: nil))
            #expect(try await recordNames(in: directoryURL).count == 1)

            // When: the cache is opened with a key.
            let encrypted = makeStorage(directoryURL, key: Self.key(1))

            // Then: it is not an entry of that key.
            #expect(await encrypted[legacyKey] == nil)

            // And making room for another one takes it away, which is what stops its name, the URL
            // in it, from staying readable on disk.
            await encrypted.freeSpace(.max)
            #expect(try await recordNames(in: directoryURL).isEmpty)
        }
    }

    @Test
    func theSweepOfOldNames_leavesTheEntriesOfTheKeyAlone() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry of the key, and an old name next to it (written by a cache with no
            // key, which sweeps nothing).
            let encrypted = makeStorage(directoryURL, key: Self.key(1))
            try await write("current", to: encrypted)
            try await write("legacy", to: makeStorage(directoryURL, key: nil))
            #expect(try await recordNames(in: directoryURL).count == 2)

            // When
            await encrypted.freeSpace(.max)

            // Then
            #expect(try await recordNames(in: directoryURL).count == 1)
            #expect(await encrypted["current"] != nil)
        }
    }

    @Test
    func aWriteThatMakesRoom_alsoSweepsTheOldNames() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given
            try await write("legacy", to: makeStorage(directoryURL, key: nil))

            // When: the cache is opened with a key and writes.
            let encrypted = makeStorage(directoryURL, key: Self.key(1))
            try await write("current", to: encrypted)

            // Then
            #expect(try await recordNames(in: directoryURL).count == 1)
            #expect(await encrypted["current"] != nil)
        }
    }

    @Test
    func withoutAKey_nothingIsSwept_whateverTheNames() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            // Given: an entry that an encryption key wrote, and an old name.
            try await write("sealed", to: makeStorage(directoryURL, key: Self.key(1)))
            try await write("legacy", to: makeStorage(directoryURL, key: nil))

            // When: a cache with no key makes room, and writes.
            let plain = makeStorage(directoryURL, key: nil)
            await plain.freeSpace(.max)
            try await write("another", to: plain)

            // Then
            #expect(try await recordNames(in: directoryURL).count == 3)
            #expect(await plain["legacy"] != nil)
        }
    }
}
