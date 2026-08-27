//
// See LICENSE for this package's licensing information.
//

import NIOFileSystem
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
import class Foundation.JSONEncoder
#endif

#if canImport(Darwin)
import class Foundation.FileManager
import struct Foundation.FileProtectionType
#endif

struct DiskStorageTests {

    private func makeCachedResponse(key: String) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://www.apple.com/\(key)",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 0, major: 1),
                headers: [],
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
            var (firstBuffer, _) = await storage.allocateBuffer(
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
            var (secondBuffer, _) = await storage.allocateBuffer(
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
    func freeSpace_whenKnownUsageFitsUnderCapacity_shouldSkipRescanAndKeepEverything() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)
            let response = makeCachedResponse(key: "k1")

            // Given: a real entry that is already over whatever capacity `freeSpace` is about
            // to be called with — a rescan would find it and evict it.
            var (buffer, _) = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: response,
                contentLength: 0,
                maximumCapacity: .max
            )
            await buffer?.writeData(Data([0x1]))
            try? await buffer?.close()
            #expect(await storage["k1"] != nil)

            // When: freeing space down to zero, but with a `knownUsage` of zero — a trusted
            // (if, here, deliberately wrong) claim that there is nothing to evict.
            let result = await storage.freeSpace(.zero, knownUsage: .zero)

            // Then: the rescan was skipped on the strength of that claim, so the over-capacity
            // entry survives, and the call reports back exactly the `knownUsage` it was given.
            #expect(result == .zero)
            #expect(await storage["k1"] != nil)
        }
    }

    @Test
    func freeSpace_whenKnownUsageExceedsCapacity_shouldRescanAndEvict() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)
            let response = makeCachedResponse(key: "k1")

            var (buffer, _) = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: response,
                contentLength: 0,
                maximumCapacity: .max
            )
            await buffer?.writeData(Data([0x1]))
            try? await buffer?.close()
            #expect(await storage["k1"] != nil)

            // When: `knownUsage` itself already claims to be over capacity, so the shortcut
            // cannot apply and the real rescan below has to run.
            let result = await storage.freeSpace(.zero, knownUsage: .max)

            // Then: the real scan found and evicted the entry, and reported the true resulting
            // total — zero, since it was the only entry — rather than the stale `knownUsage`.
            #expect(result == .zero)
            #expect(await storage["k1"] == nil)
        }
    }

    @Test
    func allocateBuffer_shouldReturnUsageReflectingTheNewEntry() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)

            let firstResponse = makeCachedResponse(key: "k1")
            let firstResponseSize = Int64(try JSONEncoder().encode(firstResponse).count)

            // Given/When: the first entry in an empty directory, so usage after it is exactly
            // its own size.
            let (_, firstUsage) = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: firstResponse,
                contentLength: 10,
                maximumCapacity: .max
            )
            #expect(firstUsage == firstResponseSize + 10)

            // When: a second entry is allocated reusing that reported usage as `knownUsage` —
            // the shape `DataCache.Storage` relies on to thread the estimate across calls.
            try? await Task.sleep(nanoseconds: 2_000_000)
            let secondResponse = makeCachedResponse(key: "k2")
            let secondResponseSize = Int64(try JSONEncoder().encode(secondResponse).count)

            let (_, secondUsage) = await storage.allocateBuffer(
                key: "k2",
                cachedResponse: secondResponse,
                contentLength: 20,
                maximumCapacity: .max,
                knownUsage: firstUsage
            )

            // Then: usage accumulates exactly, with no rescan needed in between.
            #expect(secondUsage == firstResponseSize + 10 + secondResponseSize + 20)
        }
    }

    @Test
    func diskStorage_whenDataRecordAppearsShortlyAfterResponseRecord_shouldStillFindRecord() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)

            let key = "delayedrecord"
            let date = Date()
            let bitPattern = date.timeIntervalSinceReferenceDate.bitPattern
            let recordDirectoryURL = directoryURL.appendingPathComponent(
                "\(String(bitPattern, radix: 36)).\(key).cached",
                isDirectory: true
            )
            let responseURL = recordDirectoryURL.appendingPathComponent("response.record")
            let dataURL = recordDirectoryURL.appendingPathComponent("data.record")

            let response = makeCachedResponse(key: key)
            try await FileSystem.shared.createDirectory(
                at: recordDirectoryURL.filePath,
                withIntermediateDirectories: true
            )
            try await responseURL.write(Data(JSONEncoder().encode(response)))

            // Given: "response.record" exists already, but "data.record" only shows up a few
            // milliseconds into the lookup below — the same shape a transient
            // `FileSystem.shared.info(forFileAt:)` miss leaves behind. `Record.init?` has to
            // tolerate that instead of reporting the whole record missing outright.
            async let lookup = storage[key]

            try? await Task.sleep(nanoseconds: 4_000_000)
            try await dataURL.createPathIfNeeded()

            // Then
            #expect(await lookup != nil)
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

    #if canImport(Darwin)
    private func recordDirectoryURL(in directoryURL: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        let recordName = try #require(contents.first { $0.hasSuffix(".cached") })
        return directoryURL.appendingPathComponent(recordName, isDirectory: true)
    }

    private func protectionType(atPath path: String) -> FileProtectionType? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.protectionKey] as? FileProtectionType
    }

    @Test
    func allocateBuffer_whenFileProtectionIsSet_shouldApplyItToBothRecordFilesUpFront() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            var storage = DiskStorage(directory: directoryURL)
            storage.fileProtection = .completeUntilFirstUserAuthentication

            let response = makeCachedResponse(key: "k1")

            // Given/When: a buffer is allocated but nothing has been written into it yet.
            let (buffer, _) = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: response,
                contentLength: 0,
                maximumCapacity: .max
            )
            #expect(buffer != nil)

            let recordURL = try recordDirectoryURL(in: directoryURL)
            let responsePath = recordURL.appendingPathComponent("response.record").path
            let dataPath = recordURL.appendingPathComponent("data.record").path

            // Then: "response.record" is fully written already, and "data.record" was
            // pre-created empty — both already carry the configured protection class, rather
            // than only picking it up once actual content is streamed in later.
            #expect(protectionType(atPath: responsePath) == .completeUntilFirstUserAuthentication)
            #expect(protectionType(atPath: dataPath) == .completeUntilFirstUserAuthentication)

            var mutableBuffer = buffer
            await mutableBuffer?.writeData(Data([0x1]))
            try? await mutableBuffer?.close()

            // And: writing content afterward does not reset the class already established at
            // creation.
            #expect(protectionType(atPath: dataPath) == .completeUntilFirstUserAuthentication)
        }
    }

    @Test
    func allocateBuffer_whenFileProtectionIsNil_shouldLeaveRecordFilesAtTheSystemDefault() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let storage = DiskStorage(directory: directoryURL)
            #expect(storage.fileProtection == nil)

            let response = makeCachedResponse(key: "k1")

            let (buffer, _) = await storage.allocateBuffer(
                key: "k1",
                cachedResponse: response,
                contentLength: 0,
                maximumCapacity: .max
            )
            #expect(buffer != nil)

            // Then: with no class configured, "data.record" is not even pre-created — it is
            // left entirely to `Internals.FileBuffer`'s own lazy-open behavior, unchanged from
            // before this feature existed.
            let recordURL = try recordDirectoryURL(in: directoryURL)
            let dataPath = recordURL.appendingPathComponent("data.record").path
            #expect(!FileManager.default.fileExists(atPath: dataPath))
        }
    }
    #endif
}
