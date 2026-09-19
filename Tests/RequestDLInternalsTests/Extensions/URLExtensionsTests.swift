//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct URLExtensionsTests {

    @Test
    func writeThenReadDataRoundTrips() async throws {
        try await withTemporaryFileURL("payload.bin") { url in
            // Given
            let data = Data("hello world".utf8)

            // When
            try await url.write(data)
            let readBack = try await url.readData()

            // Then
            #expect(readBack == data)
        }
    }

    @Test
    func writeReplacesExistingContent() async throws {
        try await withTemporaryFileURL("payload.bin") { url in
            // Given
            try await url.write(Data("first".utf8))

            // When
            try await url.write(Data("second".utf8))
            let readBack = try await url.readData()

            // Then
            #expect(readBack == Data("second".utf8))
        }
    }

    /// Regression coverage for the `.newFile` gap the audit flagged: `NIOFileSystem`'s own
    /// `permissions: FilePermissions? = nil` default falls back to `.defaultsForRegularFile`
    /// (owner/group/other read, `0o644`), so any call site that didn't pass `.ownerReadWrite`
    /// explicitly created a world-readable file -- a real exposure on Linux, where a request
    /// body or cached response headers spilling to a buffer file under `/tmp` would be readable
    /// by any other local user. Both `write(_:)` and `createPathIfNeeded()` now pass it.
    @Test
    func writeCreatesAFileWithOwnerOnlyPermissions() async throws {
        try await withTemporaryFileURL("payload.bin") { url in
            // When
            try await url.write(Data("hello world".utf8))

            // Then
            #expect(try posixPermissions(atPath: url.filePath.string) == 0o600)
        }
    }

    @Test
    func createPathIfNeededCreatesAFileWithOwnerOnlyPermissions() async throws {
        try await withTemporaryFileURL("created.bin", createPath: false) { url in
            // Given
            #expect(await url.isReachable == false)

            // When
            try await url.createPathIfNeeded()

            // Then
            #expect(try posixPermissions(atPath: url.filePath.string) == 0o600)
        }
    }
}

extension URLExtensionsTests {

    private struct StatError: Error {
        let path: String
        let errno: Int32
    }

    /// The file's mode bits, narrowed to the permission bits `chmod(2)` accepts (masking off the
    /// file-type bits `stat` also reports in `st_mode`). Reads straight off the OS rather than
    /// through `Internals.fileSystem`/`Internals.PortableFileSystem`, whose `Info` types don't
    /// surface permissions at all (narrowed to just `.size` -- see `PortableFileSystem.Info`'s
    /// own doc comment) -- this needs to observe what actually landed on disk, independent of
    /// either backend's own bookkeeping.
    private func posixPermissions(atPath path: String) throws -> mode_t {
        var info = stat()

        guard stat(path, &info) == 0 else {
            throw StatError(path: path, errno: errno)
        }

        return info.st_mode & 0o777
    }
}
