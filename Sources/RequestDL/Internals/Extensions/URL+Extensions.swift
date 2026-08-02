//
// See LICENSE for this package's licensing information.
//

import NIOFileSystem
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
#endif

// MARK: - Paths

extension URL {

    /// The path of this URL, resolved against its base.
    ///
    /// Exists because `URL.path(percentEncoded:)` is only available from macOS 13 and its
    /// siblings, and because the deployment targets below that still need an answer.
    ///
    /// - Parameter percentEncoded: `true` keeps the escapes, `false` returns the literal path.
    /// Pass `false` for anything that reaches the file system: a path with `%20` in it names a
    /// file with a percent sign in it.
    func absolutePath(percentEncoded: Bool = true) -> String {
        #if canImport(Darwin)
        return absoluteURL.darwin_absolutePath(percentEncoded: percentEncoded)
        #else
        return absoluteURL.unknown_absolutePath(percentEncoded: percentEncoded)
        #endif
    }

    /// This URL as a `FilePath`, which is the currency the file system layer speaks.
    ///
    /// The one place the conversion happens. Every call site used to spell out
    /// `FilePath(absolutePath(percentEncoded: false))`, and forgetting the `false` there hands
    /// the file system a name containing literal escapes.
    var filePath: FilePath {
        FilePath(absolutePath(percentEncoded: false))
    }

    #if canImport(Darwin)
    private func darwin_absolutePath(percentEncoded: Bool) -> String {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return path(percentEncoded: percentEncoded)
        } else {
            return unknown_absolutePath(percentEncoded: percentEncoded)
        }
    }
    #endif

    private func unknown_absolutePath(percentEncoded: Bool) -> String {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return ""
        }

        // `URLComponents` already keeps both forms and hands over whichever is asked for.
        //
        // The previous version encoded the path by hand and assigned the result back to
        // `components.path`, which is the decoded property, and then read that same property.
        // Assigning encoded text to the decoded side means the escapes are stored as literal
        // content, so the value only looked right by accident, and any later read of
        // `percentEncodedPath` would have come back double escaped.
        return percentEncoded ? components.percentEncodedPath : components.path
    }
}

// MARK: - File system

extension URL {

    /// Whether something exists at this location.
    var isReachable: Bool {
        get async {
            let info = try? await FileSystem.shared.info(forFileAt: filePath)
            return info != nil
        }
    }

    /// Creates an empty file here, and any missing directory above it.
    ///
    /// A no op when the file already exists, so the content of an existing file is never at
    /// risk. The previous version passed `replaceExisting: true`, which was harmless only
    /// because of the surrounding existence check, and read as the opposite of the intent.
    ///
    /// - Throws: Whatever the file system reports. Unlike the previous version, a failure to
    /// stat is propagated rather than read as "missing", so a permission problem no longer
    /// turns into an attempt to create a file that is already there.
    func createPathIfNeeded() async throws {
        let filePath = self.filePath

        guard try await FileSystem.shared.info(forFileAt: filePath) == nil else {
            return
        }

        let directoryPath = filePath.removingLastComponent()

        // `withIntermediateDirectories` covers the parents, not the leaf, so an existing
        // directory still has to be checked for.
        if try await FileSystem.shared.info(forFileAt: directoryPath) == nil {
            try await FileSystem.shared.createDirectory(
                at: directoryPath,
                withIntermediateDirectories: true
            )
        }

        let handle = try await FileSystem.shared.openFile(
            forWritingAt: filePath,
            options: .newFile(replaceExisting: false)
        )

        try await handle.close()
    }

    /// Removes whatever is here, if anything is.
    func removeIfNeeded() async throws {
        let filePath = self.filePath

        guard try await FileSystem.shared.info(forFileAt: filePath) != nil else {
            return
        }

        try await FileSystem.shared.removeItem(at: filePath)
    }
}
