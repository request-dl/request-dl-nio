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
            ?? FilePath.sharedCachesDirectory

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

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)

    // MARK: - Where there is no directory of the user's own

    /// The temporary directory is shared by every user at a path anyone can predict, and a user
    /// who gets there first can create the directory the cache is about to use and rename it from
    /// under the process. Two users cannot be had in a test, so who owns what is a parameter.

    @Test
    func ownedDirectory_whenAbsent_isCreatedOwnerOnly() throws {
        // Given
        let parent = try makeParent(mode: 0o700)
        defer { remove(parent) }

        // When
        let directory = FilePath.ownedDirectory(named: "cache", under: parent)

        // Then
        #expect(directory == parent.appending("cache"))
        #expect(try mode(of: parent.appending("cache")) == 0o700)
    }

    @Test
    func ownedDirectory_whenItIsTheOwnersAlready_isUsed() throws {
        // Given
        let parent = try makeParent(mode: 0o700)
        defer { remove(parent) }

        _ = FilePath.ownedDirectory(named: "cache", under: parent)

        // When
        let again = FilePath.ownedDirectory(named: "cache", under: parent)

        // Then
        #expect(again == parent.appending("cache"))
    }

    @Test
    func ownedDirectory_whenAnotherUserOwnsIt_isNotUsed() throws {
        // Given: the directory is this user's, and the caller asks for a different owner.
        let parent = try makeParent(mode: 0o700)
        defer { remove(parent) }

        let someoneElse = UInt32(geteuid()) + 1

        // When / Then
        #expect(FilePath.ownedDirectory(named: "cache", under: parent, owner: someoneElse) == nil)
    }

    @Test(arguments: [0o755, 0o750, 0o770, 0o707] as [Int])
    func ownedDirectory_whenOthersCanGetInto_isNotUsed(_ mode: Int) throws {
        // Given: a directory of this user's that group or others can read or write.
        let parent = try makeParent(mode: 0o700)
        defer { remove(parent) }

        let path = parent.appending("cache")
        try FileManager.default.createDirectory(atPath: path.string, withIntermediateDirectories: false)
        #expect(chmod(path.string, mode_t(mode)) == 0)

        // When / Then
        #expect(FilePath.ownedDirectory(named: "cache", under: parent) == nil)
    }

    /// Anyone can plant a symbolic link in the temporary directory, to somewhere that is theirs.
    @Test
    func ownedDirectory_whenASymbolicLinkIsThere_isNotFollowed() throws {
        // Given
        let parent = try makeParent(mode: 0o700)
        defer { remove(parent) }

        let target = parent.appending("target")
        try FileManager.default.createDirectory(atPath: target.string, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            atPath: parent.appending("cache").string,
            withDestinationPath: target.string
        )

        // When / Then
        #expect(FilePath.ownedDirectory(named: "cache", under: parent) == nil)
    }

    /// Where every user can write without the sticky bit, any of them can rename the directory
    /// away, whoever owns it.
    @Test
    func ownedDirectory_whenTheParentLetsOthersRenameIt_isNotUsed() throws {
        // Given
        let parent = try makeParent(mode: 0o777)
        defer { remove(parent) }

        // When / Then
        #expect(FilePath.ownedDirectory(named: "cache", under: parent) == nil)
    }

    /// The temporary directory of an ordinary machine: every user writes in it and the sticky bit
    /// keeps them from touching each other's entries.
    @Test
    func ownedDirectory_whenTheParentIsWorldWritableAndSticky_isUsed() throws {
        // Given
        let parent = try makeParent(mode: 0o1777)
        defer { remove(parent) }

        // When
        let directory = FilePath.ownedDirectory(named: "cache", under: parent)

        // Then
        #expect(directory == parent.appending("cache"))
    }

    @Test
    func ownedDirectory_whenTheParentIsMissing_isNotUsed() {
        let parent = FilePath.temporaryDirectory.appending("requestdl-missing-\(UUID().uuidString)")

        #expect(FilePath.ownedDirectory(named: "cache", under: parent) == nil)
    }

    @Test
    func exclusiveDirectory_isNewEveryTime_andOwnerOnly() throws {
        // Given
        let parent = try makeParent(mode: 0o700)
        defer { remove(parent) }

        // When
        let first = FilePath.exclusiveDirectory(prefix: "cache", under: parent)
        let second = FilePath.exclusiveDirectory(prefix: "cache", under: parent)

        // Then
        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second)
        #expect(first?.removingLastComponent() == parent)

        for directory in [first, second].compactMap({ $0 }) {
            #expect(try mode(of: directory) == 0o700)
        }
    }

    @Test
    func exclusiveDirectory_whenTheParentIsMissing_isNil() {
        let parent = FilePath.temporaryDirectory.appending("requestdl-missing-\(UUID().uuidString)")

        #expect(FilePath.exclusiveDirectory(prefix: "cache", under: parent) == nil)
    }

    /// The directory the cache falls back to is the process's, not the temporary directory: owner
    /// only, and the same every time it is asked.
    @Test
    func sharedCachesDirectory_isPrivateAndStable() throws {
        // Given
        let directory = FilePath.sharedCachesDirectory

        // Then
        #expect(directory != FilePath.temporaryDirectory)
        #expect(directory.string.hasPrefix(FilePath.temporaryDirectory.string))
        #expect(try mode(of: directory) == 0o700)
        #expect(FilePath.sharedCachesDirectory == directory)
    }

    #endif

    // MARK: - Helpers

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)
    private func makeParent(mode: Int) throws -> FilePath {
        let parent = FilePath.temporaryDirectory.appending("requestdl-owned-\(UUID().uuidString)")

        try FileManager.default.createDirectory(atPath: parent.string, withIntermediateDirectories: false)
        #expect(chmod(parent.string, mode_t(mode)) == 0)

        return parent
    }

    private func remove(_ path: FilePath) {
        _ = chmod(path.string, 0o700)
        try? FileManager.default.removeItem(atPath: path.string)
    }
    #endif

    private func mode(of path: FilePath) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.string)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
