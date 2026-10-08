//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// A cache entry is a directory named after the URL it caches, so everything the cache creates
/// is owner only, or those URLs (query tokens included) are listed to anyone on a machine where
/// the cache lives in a shared directory.
struct DataCacheDirectoryPermissionsTests {

    @Test
    func cache_whenAnEntryIsWrittenToDisk_everyDirectoryItCreatesIsOwnerOnly() async throws {
        // Given
        let dataCache = DataCache(suiteName: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dataCache.directoryURL) }

        dataCache.memoryCapacity = .zero
        dataCache.diskCapacity = 8 * 1_024 * 1_024

        let key = "https://example.com/items?token=secret"

        // When
        await dataCache.setCachedData(
            await CachedData(
                response: ResponseHead(
                    url: URL(string: key),
                    status: .init(code: 200, reason: "Ok"),
                    version: .init(minor: 1, major: 1),
                    headers: HTTPHeaders([("Content-Length", "5")]),
                    isKeepAlive: false
                ),
                policy: .disk,
                data: Data("hello".utf8)
            ),
            forKey: key
        )
        await dataCache.waitUntilIdle()

        // Then: the suite's directory and the entry directory inside it.
        let suiteDirectory = dataCache.directoryURL
        #expect(try mode(of: suiteDirectory) == 0o700)

        let entries = try FileManager.default.contentsOfDirectory(
            at: suiteDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(!entries.isEmpty)

        for entry in entries {
            #expect(try mode(of: entry) == 0o700, "\(entry.lastPathComponent)")
        }
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
