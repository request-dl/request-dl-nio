//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#else
import Foundation
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

extension Internals {

    /// Thrown when a directory could not be opened or read.
    package struct DirectoryListingError: Error, Sendable, Hashable {

        /// The `errno` of the failing call, or `0` where the platform reports none.
        package let code: Int32
    }

    /// The names of the entries in the directory at `path`, in no particular order and without
    /// `.` and `..`.
    ///
    /// Reads the directory in one pass on the file system pool. `NIOFileSystem`'s own listing
    /// was measured at about two milliseconds an entry for a directory of a few thousand
    /// (4.5 s for 2500, against 1 ms for the same names read directly), which the cache paid on
    /// the first lookup after a launch, and nothing here needs more than the names.
    ///
    /// - Throws: ``DirectoryListingError`` if the directory cannot be opened.
    package static func directoryEntryNames(atPath path: String) async throws -> [String] {
        try await FileSystemManager.run { try readDirectoryEntryNames(atPath: path) }
    }

    /// When the entry at `path` was last modified, or `nil` where it cannot be read.
    ///
    /// For a directory this moves when an entry is created in it or moved into it, which is what
    /// tells a directory somebody is still filling from one nobody has touched in a long while.
    package static func modificationDate(atPath path: String) async -> Date? {
        try? await FileSystemManager.run { try readModificationDate(atPath: path) }
    }

    #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)

    private static func readModificationDate(atPath path: String) throws -> Date {
        var info = stat()

        guard stat(path, &info) == 0 else {
            throw DirectoryListingError(code: errno)
        }

        #if canImport(Darwin)
        let time = info.st_mtimespec
        #else
        let time = info.st_mtim
        #endif

        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
    }

    private static func readDirectoryEntryNames(atPath path: String) throws -> [String] {
        guard let directory = opendir(path) else {
            throw DirectoryListingError(code: errno)
        }

        defer { closedir(directory) }

        var names: [String] = []

        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pointer.pointee)) {
                    String(cString: $0)
                }
            }

            if name != ".", name != ".." {
                names.append(name)
            }
        }

        return names
    }

    #else

    private static func readModificationDate(atPath path: String) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)

        guard let date = attributes[.modificationDate] as? Date else {
            throw DirectoryListingError(code: 0)
        }

        return date
    }

    private static func readDirectoryEntryNames(atPath path: String) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            throw DirectoryListingError(code: 0)
        }
    }

    #endif
}
