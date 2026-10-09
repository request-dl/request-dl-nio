//
// See LICENSE for this package's licensing information.
//

import Foundation
import SystemPackage
import Testing

@testable import RequestDLInternals

/// Where the cache lives and who can see into it.
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

    #if os(Linux)
    /// The property itself, with the process's real environment: the cache lives where the helper
    /// above says when it can say, and under the temporary directory only when it cannot.
    @Test
    func cachesDirectory_onLinux_isTheUsersCacheDirectoryWhenThereIsOne() {
        let expected =
            FilePath.xdgCacheDirectory(environment: ProcessInfo.processInfo.environment)
            ?? FilePath.temporaryDirectory

        #expect(FilePath.cachesDirectory == expected)
    }
    #endif

    // MARK: - Who

    /// The directories holding a cache are named after the URL they cache, so they must not be
    /// readable by every user of the machine, or the URLs (query tokens included) can be listed
    /// by anyone. Every directory the call creates, the ones above the leaf too, is owner only.
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
