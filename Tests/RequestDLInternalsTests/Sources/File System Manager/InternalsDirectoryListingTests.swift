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
        try await withTemporaryFileURL(createPath: false) { directoryURL in
            await #expect(throws: Internals.DirectoryListingError.self) {
                _ = try await Internals.directoryEntryNames(atPath: directoryURL.path)
            }
        }
    }

    @Test
    func names_ofAFile_throws() async throws {
        try await withTemporaryFileURL("file.txt") { fileURL in
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
}
