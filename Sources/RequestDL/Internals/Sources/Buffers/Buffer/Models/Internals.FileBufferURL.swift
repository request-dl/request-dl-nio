/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Internals {

    struct FileBufferURL: BufferURL {

        // MARK: - Internal static properties

        static var temporaryURL: Internals.FileBufferURL {
            let timestamp = Int(Date.timeIntervalSinceReferenceDate)
            let pathComponent = Data("\(timestamp).\(UUID())".utf8).base64EncodedString()

            return .init(
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(pathComponent)
                    .appendingPathExtension("buffer")
            )
        }

        // MARK: - Internal properties

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
        private let url: Foundation.URL

        // MARK: - Inits

        init(_ url: Foundation.URL) {
            self.url = url
            self._path = url.absolutePath(percentEncoded: false)
        }

        func isResourceAvailable() -> Bool {
            FileManager.default.fileExists(atPath: _path)
        }

        func createResourceIfNeeded() {
            guard !isResourceAvailable() else {
                return
            }

            let directoryURL = url.deletingLastPathComponent()

            if directoryURL.hasDirectoryPath, !directoryURL.isReachable {
                try? FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }

            try? Data().write(to: url)
        }

        func absoluteURL() -> Foundation.URL {
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
