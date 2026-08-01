//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    struct FileBufferURL: BufferURL {

        // MARK: - Internal static properties

        static var temporaryURL: Internals.FileBufferURL {
            let timestamp = Int(Date.timeIntervalSinceReferenceDate)

            // No base64 here. The alphabet includes `/`, which `appendingPathComponent` reads
            // as a separator, so the encoding could quietly turn one file name into a nested
            // path. And it was encoding a string that is already safe: digits, a dot, and a
            // UUID in hexadecimal with hyphens.
            let pathComponent = "\(timestamp).\(UUID().uuidString)"

            return .init(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent(pathComponent)
                    .appendingPathExtension("buffer"),
                isTemporary: true
            )
        }

        // MARK: - Internal properties

        /// - Important: This is a stat call, not a stored value.
        var writtenBytes: Int {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: _path)
                return attributes[.size] as? Int ?? .zero
            } catch {
                return .zero
            }
        }

        // MARK: - Private properties

        private let _path: String
        private let url: URL

        // Only a URL this type minted itself is one it may delete. A caller supplied path
        // belongs to the caller.
        private let isTemporary: Bool

        // MARK: - Inits

        init(_ url: URL) {
            self.init(url: url, isTemporary: false)
        }

        private init(url: URL, isTemporary: Bool) {
            self.url = url
            self._path = url.absolutePath(percentEncoded: false)
            self.isTemporary = isTemporary
        }

        // MARK: - Internal static methods

        static func make(from url: URL) -> Internals.FileBufferURL? {
            .init(url)
        }

        // MARK: - Internal methods

        func isResourceAvailable() -> Bool {
            FileManager.default.fileExists(atPath: _path)
        }

        func createResourceIfNeeded() {
            guard !isResourceAvailable() else {
                return
            }

            let directoryURL = url.deletingLastPathComponent()

            if !directoryURL.isReachable {
                try? FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }

            // `.withoutOverwriting` is `O_EXCL`, so the create is atomic. The check above is
            // only a fast path: without the flag, two cursors reaching this at the same time
            // both see the file missing and the second one truncates what the first just
            // wrote.
            try? Data().write(to: url, options: .withoutOverwriting)
        }

        func truncate() {
            guard isResourceAvailable() else {
                return
            }

            try? Data().write(to: url)
        }

        func removeIfTemporary() {
            guard isTemporary else {
                return
            }

            try? FileManager.default.removeItem(at: url)
        }

        func absoluteURL() -> URL {
            url
        }
    }
}

extension URL {

    var isReachable: Bool {
        FileManager.default.fileExists(
            atPath: absolutePath(percentEncoded: false)
        )
    }
}
