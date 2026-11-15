//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsDirectoryListingTests {

    @Test
    func names_listsFilesDirectoriesAndHiddenEntries_withoutDotAndDotDot() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            let manager = FileManager.default
            try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try Data([1]).write(to: directoryURL.appendingPathComponent("file.txt"))
            try Data([1]).write(to: directoryURL.appendingPathComponent(".hidden"))
            try manager.createDirectory(
                at: directoryURL.appendingPathComponent("folder.cached"),
                withIntermediateDirectories: true
            )

            let names = try await Internals.directoryEntryNames(atPath: directoryURL.path)

            #expect(Set(names) == [".hidden", "file.txt", "folder.cached"])
            #expect(names.count == 3)
        }
    }

    @Test
    func names_ofAnEmptyDirectory_isEmpty() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            #expect(try await Internals.directoryEntryNames(atPath: directoryURL.path).isEmpty)
        }
    }

    @Test
    func names_ofAMissingDirectory_throws() async throws {
        _ = try await withTemporaryFileURL(createPath: false) { directoryURL in
            await #expect(throws: Internals.DirectoryListingError.self) {
                _ = try await Internals.directoryEntryNames(atPath: directoryURL.path)
            }
        }
    }

    @Test
    func names_ofAFile_throws() async throws {
        _ = try await withTemporaryFileURL("file.txt") { fileURL in
            await #expect(throws: Internals.DirectoryListingError.self) {
                _ = try await Internals.directoryEntryNames(atPath: fileURL.path)
            }
        }
    }

    @Test
    func names_ofAManyEntryDirectory_returnsEveryOne() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            for index in 0..<1_500 {
                try Data().write(to: directoryURL.appendingPathComponent("entry-\(index)"))
            }

            let names = try await Internals.directoryEntryNames(atPath: directoryURL.path)

            #expect(names.count == 1_500)
            #expect(Set(names).count == 1_500)
        }
    }

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)

    /// `readdir` answers `NULL` for the end of the directory and for a failure alike, and only
    /// `errno` tells them apart. A failure partway through must not look like the end.
    @Test
    func entryNames_whenAReadFailsPartway_throwsInsteadOfReturningAShortListing() throws {
        let entries = ["one", "two", "three"].map { Self.makeEntry(named: $0) }
        defer {
            for entry in entries {
                entry.deallocate()
            }
        }

        var reads = 0

        #expect(throws: Internals.DirectoryListingError(code: EIO)) {
            try Internals.entryNames(of: 0) { _ in
                defer { reads += 1 }

                guard reads < 2 else {
                    errno = EIO
                    return nil
                }

                return entries[reads]
            }
        }

        #expect(reads == 3)
    }

    @Test
    func entryNames_whenTheEndComesWithAStaleErrno_stillReturnsTheListing() throws {
        let entry = Self.makeEntry(named: "only")
        defer { entry.deallocate() }

        // An earlier, unrelated failure left `errno` set.
        errno = ENOENT
        var reads = 0

        let names = try Internals.entryNames(of: 0) { _ in
            defer { reads += 1 }
            return reads == 0 ? entry : nil
        }

        #expect(names == ["only"])
    }

    /// Copied byte by byte: `strlcpy` is missing from older Glibc versions.
    private static func makeEntry(named name: String) -> UnsafeMutablePointer<dirent> {
        let entry = UnsafeMutablePointer<dirent>.allocate(capacity: 1)
        entry.initialize(to: dirent())

        withUnsafeMutableBytes(of: &entry.pointee.d_name) { bytes in
            for (index, byte) in name.utf8.enumerated() {
                bytes[index] = byte
            }
        }

        return entry
    }

    #endif

    @Test
    func modificationDate_ofADirectory_movesWhenAnEntryIsCreatedInIt() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let before = try #require(await Internals.modificationDate(atPath: directoryURL.path))
            #expect(abs(before.timeIntervalSinceNow) < 60)

            try await Task.sleep(nanoseconds: 50_000_000)
            try Data().write(to: directoryURL.appendingPathComponent("entry"))

            let after = try #require(await Internals.modificationDate(atPath: directoryURL.path))
            #expect(after > before)
        }
    }

    @Test
    func modificationDate_ofAMissingPath_isNil() async throws {
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            #expect(await Internals.modificationDate(atPath: directoryURL.path) == nil)
        }
    }
}
