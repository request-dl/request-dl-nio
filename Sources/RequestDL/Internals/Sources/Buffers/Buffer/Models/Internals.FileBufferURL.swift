//
// See LICENSE for this package's licensing information.
//

import NIOFileSystem
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Date
import struct Foundation.UUID
import class Foundation.ProcessInfo
#endif

extension Internals {

    /// Addresses a file on disk.
    ///
    /// Metadata operations go through `NIOFileSystem`, which is async and offloads to an I/O
    /// thread pool. The byte level reads and writes happen in ``Internals/FileStreamBuffer``.
    ///
    /// Creation, existence and removal delegate to the `URL` extensions rather than reimplement
    /// them, so there is one description of what "this file exists" means.
    struct FileBufferURL: BufferURL {

        // MARK: - Internal static properties

        /// A path inside the system temporary directory that nothing else holds.
        ///
        /// The file is not created here. Whoever writes first creates it, and the storage that
        /// owns this URL removes it when it goes away.
        static var temporaryURL: Internals.FileBufferURL {
            let timestamp = Int(Date.timeIntervalSinceReferenceDate)
            let pathComponent = "\(timestamp).\(UUID().uuidString).buffer"
            let path = FilePath.temporaryDirectory.appending(pathComponent)

            return .init(path: path, url: URL(fileURLWithPath: path.string), isTemporary: true)
        }

        // MARK: - Internal properties

        /// The path the streams open against.
        ///
        /// Derived once, at init. The previous version rebuilt a `FilePath` from a `String` on
        /// every call, including inside the open path of both streams.
        let path: FilePath

        /// - Important: This is a stat call, not a stored value.
        /// - Returns: Zero when the file is missing or unreadable, which is what an empty
        /// buffer looks like to everything upstream.
        var writtenBytes: Int {
            get async {
                do {
                    guard let info = try await FileSystem.shared.info(forFileAt: path) else {
                        return .zero
                    }

                    return Int(info.size)
                } catch {
                    return .zero
                }
            }
        }

        // MARK: - Private properties

        private let url: URL
        private let isTemporary: Bool

        // MARK: - Inits

        init(_ url: URL) {
            self.init(path: url.filePath, url: url, isTemporary: false)
        }

        private init(path: FilePath, url: URL, isTemporary: Bool) {
            self.path = path
            self.url = url
            self.isTemporary = isTemporary
        }

        // MARK: - Internal static methods

        static func make(from url: URL) -> Internals.FileBufferURL? {
            .init(url)
        }

        // MARK: - Internal methods

        func isResourceAvailable() async -> Bool {
            await url.isReachable
        }

        /// - Important: Failures are swallowed. The open that follows reports the same problem
        /// with better context, and there is nothing useful to do here on the way past.
        func createResourceIfNeeded() async {
            try? await url.createPathIfNeeded()
        }

        /// Empties the file.
        ///
        /// - Warning: This is allowed to replace the file rather than shorten it in place, so
        /// any descriptor already open against it may end up addressing an unlinked object.
        /// Callers close their streams first.
        func truncate() async {
            guard await isResourceAvailable() else {
                return
            }

            do {
                let handle = try await FileSystem.shared.openFile(
                    forWritingAt: path,
                    options: .newFile(replaceExisting: true)
                )

                try await handle.close()
            } catch {}
        }

        func removeIfTemporary() async {
            guard isTemporary else {
                return
            }

            try? await url.removeIfNeeded()
        }

        func absoluteURL() -> URL {
            url
        }
    }
}
