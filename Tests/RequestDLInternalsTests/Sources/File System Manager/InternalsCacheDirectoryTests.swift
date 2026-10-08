//
// See LICENSE for this package's licensing information.
//

import Foundation
import SystemPackage
import Testing

@testable import RequestDLInternals

/// Where the cache lives and who can see into it (audit findings S5 and V2).
struct InternalsCacheDirectoryTests {

    // MARK: - Where

    @Test
    func xdgCacheDirectory_whenXDGCacheHomeIsAbsolute_isUsed() {
        let directory = FilePath.xdgCacheDirectory(environment: [
            "XDG_CACHE_HOME": "/var/cache/me",
            "HOME": "/home/me",
        ])

        #expect(directory == FilePath("/var/cache/me"))
    }

    @Test
    func xdgCacheDirectory_whenXDGCacheHomeIsMissing_isDotCacheUnderHome() {
        let directory = FilePath.xdgCacheDirectory(environment: ["HOME": "/home/me"])

        #expect(directory == FilePath("/home/me/.cache"))
    }

    /// The specification calls a relative `$XDG_CACHE_HOME` invalid and says to ignore it.
    @Test(arguments: ["", "relative/cache", "~/cache"])
    func xdgCacheDirectory_whenXDGCacheHomeIsNotAbsolute_fallsBackToHome(_ value: String) {
        let directory = FilePath.xdgCacheDirectory(environment: [
            "XDG_CACHE_HOME": value,
            "HOME": "/home/me",
        ])

        #expect(directory == FilePath("/home/me/.cache"))
    }

    @Test
    func xdgCacheDirectory_whenThereIsNoUsableHome_isNil() {
        #expect(FilePath.xdgCacheDirectory(environment: [:]) == nil)
        #expect(FilePath.xdgCacheDirectory(environment: ["HOME": ""]) == nil)
        #expect(FilePath.xdgCacheDirectory(environment: ["HOME": "relative"]) == nil)
    }

    // MARK: - Who

    /// Regression test (audit finding S5): the directories holding a cache are named after the
    /// URL they cache, and were created readable by every user of the machine, so the URLs
    /// (query tokens included) could be listed by anyone. Every directory the call creates,
    /// the ones above the leaf too, is now owner only.
    @Test
    func createDirectory_withOwnerOnlyPermissions_createsEveryLevelAsOwnerOnly() async throws {
        // Given
        let root = FilePath.temporaryDirectory.appending("requestdl-test-\(UUID().uuidString)")
        let leaf = root.appending("one").appending("two").appending("three")

        defer { try? FileManager.default.removeItem(atPath: root.string) }

        // When
        try await Internals.fileSystem.createDirectory(
            at: leaf,
            withIntermediateDirectories: true,
            permissions: .ownerReadWriteExecute
        )

        // Then
        var path = leaf
        while path != root.removingLastComponent() {
            #expect(try mode(of: path) == 0o700, "\(path)")
            path = path.removingLastComponent()
        }
    }

    // MARK: - Helpers

    private func mode(of path: FilePath) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.string)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
