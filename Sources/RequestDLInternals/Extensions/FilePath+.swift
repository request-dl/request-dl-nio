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

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
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
        #elseif os(Linux)
        if let directory = xdgCacheDirectory(environment: ProcessInfo.processInfo.environment) {
            return directory
        }
        #endif

        return sharedCachesDirectory
    }

    /// Where the cache goes when there is no per-user directory for it, which is the temporary
    /// directory every user of the machine can write to. Not the temporary directory itself: a
    /// directory of this process's user in it, that nobody else made or can rename away
    /// (``ownedDirectory(named:under:owner:)``), and, when the place cannot be trusted, one
    /// with a name nobody could have guessed, that lasts as long as the process does
    /// (``exclusiveDirectory(prefix:under:)``). Where there is no such thing to check (Windows),
    /// the temporary directory, as it always was.
    ///
    /// Resolved once: the fallback must be the same every time it is asked.
    package static var sharedCachesDirectory: FilePath { sharedCachesDirectoryOnce }

    private static let sharedCachesDirectoryOnce: FilePath = {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)
        let temporary = temporaryDirectory

        return ownedDirectory(named: "request-dl-nio-\(geteuid())", under: temporary)
            ?? exclusiveDirectory(prefix: "request-dl-nio", under: temporary)
            ?? temporary
        #else
        return temporaryDirectory
        #endif
    }()

    /// The per-user cache directory of the XDG Base Directory specification: `$XDG_CACHE_HOME`,
    /// or `$HOME/.cache` when it is not set. `nil` when neither names a usable absolute path,
    /// and the caller falls back to the temporary directory.
    ///
    /// The specification says a relative `$XDG_CACHE_HOME` is invalid and must be ignored. A
    /// per-user directory is the point: the temporary directory is shared by every user of the
    /// machine, at a path anyone can predict.
    ///
    /// Takes the environment as a parameter so it can be tested without changing the process's.
    package static func xdgCacheDirectory(environment: [String: String]) -> FilePath? {
        if let cacheHome = environment["XDG_CACHE_HOME"], cacheHome.hasPrefix("/") {
            return FilePath(cacheHome)
        }

        if let home = environment["HOME"], home.hasPrefix("/") {
            return FilePath(home).appending(".cache")
        }

        return nil
    }
}
