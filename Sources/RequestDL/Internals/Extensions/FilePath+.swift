//
// See LICENSE for this package's licensing information.
//

import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.ProcessInfo
#endif

extension FilePath {

    /// The system temporary directory.
    ///
    /// Resolved from the environment rather than from `FileManager`, which is not part of
    /// `FoundationEssentials`. The hardcoded fallbacks only matter for a process started
    /// without the usual environment, such as some launch daemons and CI runners.
    ///
    /// ## Why not `FileSystem.shared.temporaryDirectory`
    ///
    /// That is the NIO one, and it is the natural answer, but it is `async throws`. This has to
    /// stay synchronous: `DataCache.shared` is a `static let`, and a stored property cannot be
    /// initialised from an asynchronous call. Making it work would mean turning every public
    /// `DataCache` initializer `async` and finding another shape for `shared`.
    ///
    /// Reading `TMPDIR` is what Darwin's own temporary directory resolves to anyway, so this
    /// lands in the same place `FileManager.default.temporaryDirectory` did.
    static var temporaryDirectory: FilePath {
        let environment = ProcessInfo.processInfo.environment

        // Unix-like platforms, macOS included.
        if let tmpdir = environment["TMPDIR"], !tmpdir.isEmpty {
            return FilePath(tmpdir)
        }

        // Windows.
        if let temp = environment["TEMP"], !temp.isEmpty {
            return FilePath(temp)
        }

        if let tmp = environment["TMP"], !tmp.isEmpty {
            return FilePath(tmp)
        }

        #if os(Windows)
        return FilePath("C:\\Windows\\Temp")
        #elseif os(Linux) || os(Android)
        return FilePath("/tmp")
        #else
        return FilePath("/private/tmp")
        #endif
    }
}
