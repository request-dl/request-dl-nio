//
// See LICENSE for this package's licensing information.
//

import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.ProcessInfo
#endif

#if canImport(Darwin)
import class Foundation.FileManager
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
    package static var temporaryDirectory: FilePath {
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

    /// The directory appropriate for data that should persist between launches but can be
    /// regenerated, such as the on-disk cache.
    ///
    /// Apple's guidance is explicit about this split: the temporary directory can be purged by
    /// the system at any moment, including while the app is still running, so anything that
    /// needs to survive past the current request does not belong there. `Library/Caches` is
    /// still purgeable under disk pressure, but only between launches, which is what a cache
    /// actually wants.
    ///
    /// `FileManager` is not part of `FoundationEssentials`, so this only resolves through it on
    /// Darwin, where the full `Foundation` is available. Everywhere else there is no equivalent
    /// standard location, so this falls back to ``temporaryDirectory``.
    package static var cachesDirectory: FilePath {
        #if canImport(Darwin)
        if let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return FilePath(url.path)
        }
        #endif

        return temporaryDirectory
    }
}
