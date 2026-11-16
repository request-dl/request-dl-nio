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
    /// - Throws: ``DirectoryListingError`` if the directory cannot be opened or a read of it fails.
    /// A listing that would stop short is an error, never a shorter list.
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

        return try entryNames(of: directory, reading: readdir)
    }

    /// The names `next` hands back for `directory`, until it says there are no more.
    ///
    /// `readdir` returns `NULL` both at the end of the directory and on an error, and only `errno`
    /// tells them apart: it is not touched at the end and set on an error. So it is cleared before
    /// each call, and a `NULL` with it set is an error, not the end. Reading it as the end would
    /// hand back a listing that stops short, as if the rest of the directory were not there.
    ///
    /// `next` is a parameter, and `Directory` is left open, so a test can make the read fail and
    /// no platform's `DIR` type has to be spelled out.
    package static func entryNames<Directory>(
        of directory: Directory,
        reading next: (Directory) -> UnsafeMutablePointer<dirent>?
    ) throws -> [String] {
        var names: [String] = []

        while true {
            errno = 0

            guard let entry = next(directory) else {
                guard errno == 0 else {
                    throw DirectoryListingError(code: errno)
                }

                return names
            }

            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pointer.pointee)) {
                    String(cString: $0)
                }
            }

            if name != ".", name != ".." {
                names.append(name)
            }
        }
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
