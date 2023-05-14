/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
            let size = try? FileManager.default.attributesOfItem(
                atPath: _path
            )[.size] as? Int

            return size ?? .zero
        }

        // MARK: - Private properties

        private var _path: String {
            url.absolutePath(percentEncoded: false)
        }

        private let url: Foundation.URL

        // MARK: - Inits

        init(_ url: Foundation.URL) {
            self.url = url
        }

        func isResourceAvailable() -> Bool {
            (try? url.checkResourceIsReachable()) ?? false
        }

        func createResourceIfNeeded() {
            guard !isResourceAvailable() else {
                return
            }

            let directoryURL = url.deletingLastPathComponent()

            if directoryURL.hasDirectoryPath, (try? directoryURL.checkResourceIsReachable()) ?? false  {
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
