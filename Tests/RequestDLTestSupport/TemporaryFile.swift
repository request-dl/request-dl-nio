//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.UUID
#endif

/// The system temporary directory, without `FileManager`.
///
/// `FileManager` is not part of `FoundationEssentials`, so a test file that imports only that
/// module cannot reach `temporaryDirectoryURL`. This resolves the same
/// location: on Darwin both come from `TMPDIR`.
var temporaryDirectoryURL: URL {
    URL(fileURLWithPath: FilePath.temporaryDirectory.string, isDirectory: true)
}

/// Runs `body` with a scratch file path, and removes it afterwards.
///
/// ## Why a closure instead of `defer`
///
/// Teardown is asynchronous now: `URL.removeIfNeeded()` goes through `NIOFileSystem`. `defer`
/// cannot await, and neither can `deinit`, so the two shapes the tests reached for do not work:
///
/// - `defer { url.scheduleRemoval() }` does not compile.
/// - `defer { url.scheduleRemoval() }` compiles and is fire and forget. The
///   test finishes before the removal runs, so a suite that reuses a name races itself.
///
/// A closure keeps the cleanup ordered, and runs it on the throwing path too.
func withTemporaryFileURL<Result>(
    _ pathComponents: String...,
    createPath: Bool = true,
    perform body: (URL) async throws -> Result
) async throws -> Result {
    // The scratch root this call owns. Teardown removes *this*, never
    // `url.deletingLastPathComponent()`: with no path components that parent is the shared
    // system temporary directory itself, and removing it recursively wipes every other
    // concurrently running test's scratch files — including the file-backed buffers
    // `Internals.FileBufferURL.temporaryURL` places directly in there.
    let rootURL =
        temporaryDirectoryURL
        .appendingPathComponent("RequestDL.\(UUID().uuidString)", isDirectory: true)

    var url = rootURL

    for component in pathComponents {
        url = url.appendingPathComponent(component)
    }

    if createPath {
        try await url.createPathIfNeeded()
    }

    do {
        let result = try await body(url)
        try? await rootURL.removeIfNeeded()
        return result
    } catch {
        try? await rootURL.removeIfNeeded()
        throw error
    }
}

extension URL {

    /// Queues removal of this path, for teardown where `defer` cannot await.
    ///
    /// - Warning: Fire and forget. It is **not** ordered against the end of the test, so only
    /// use it on paths that carry a UUID, where a straggler cannot collide with the next run.
    /// Where the cleanup has to happen before the test returns, use
    /// ``withTemporaryFileURL(_:createPath:perform:)`` instead.
    func scheduleRemoval() {
        Task.detached { try? await self.removeIfNeeded() }
    }
}
