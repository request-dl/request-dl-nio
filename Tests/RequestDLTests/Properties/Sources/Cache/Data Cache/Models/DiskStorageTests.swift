//
// See LICENSE for this package's licensing information.
//

import NIOFileSystem
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import class Foundation.JSONEncoder
#endif

struct DiskStorageTests {

    private func makeCachedResponse(key: String) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://www.apple.com/\(key)",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 0, major: 1),
                headers: [:],
                isKeepAlive: true
            ),
            policy: .all
        )
    }

    @Test
    func diskStorage_whenFreeingSpaceBelowTotalUsage_shouldEvictOnlyTheOldestEntries() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)

            let firstResponse = makeCachedResponse(key: "k1")
            try? await Task.sleep(nanoseconds: 2_000_000)
            let secondResponse = makeCachedResponse(key: "k2")

            let firstSize = Int64(try JSONEncoder().encode(firstResponse).count)
            let secondSize = Int64(try JSONEncoder().encode(secondResponse).count)

            // Given: a first entry, written with plenty of room. The data file has to actually
            // exist on disk for the record to be discoverable later, so a byte is written and
            // the buffer closed.
            var firstBuffer = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: firstResponse,
                contentLength: 0,
                maximumCapacity: firstSize + secondSize
            )
            #expect(firstBuffer != nil)
            await firstBuffer?.writeData(Data([0x1]))
            try? await firstBuffer?.close()
            #expect(await storage["k1"] != nil)

            // When: a second entry is allocated with a capacity that only has room for itself
            // plus a sliver more — not enough to also keep the first entry around.
            var secondBuffer = await storage.allocateBuffer(
                key: "k2",
                cachedResponse: secondResponse,
                contentLength: 0,
                maximumCapacity: secondSize + 1
            )
            await secondBuffer?.writeData(Data([0x1]))
            try? await secondBuffer?.close()

            // Then: the oldest entry was evicted to free the space, the new one was kept.
            #expect(secondBuffer != nil)
            #expect(await storage["k1"] == nil)
            #expect(await storage["k2"] != nil)
        }
    }

    @Test
    func diskStorage_whenResponseRecordCannotBeReadAsAFile_shouldReturnNil() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)

            let key = "brokenrecord"
            let date = Date()
            let bitPattern = date.timeIntervalSinceReferenceDate.bitPattern
            let recordDirectoryURL = directoryURL.appendingPathComponent(
                "\(String(bitPattern, radix: 36)).\(key).cached",
                isDirectory: true
            )
            let responseURL = recordDirectoryURL.appendingPathComponent("response.record")
            let dataURL = recordDirectoryURL.appendingPathComponent("data.record")

            // Given: a record directory whose "response.record" is itself a directory, so the
            // record's existence check (`info(forFileAt:)`) succeeds but actually opening it
            // for reading fails.
            try await FileSystem.shared.createDirectory(
                at: responseURL.filePath,
                withIntermediateDirectories: true
            )
            try await dataURL.createPathIfNeeded()

            // Then
            #expect(await storage[key] == nil)
        }
    }
}
