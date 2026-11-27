//
// See LICENSE for this package's licensing information.
//

import SystemPackage

#if canImport(NIOCore)
import NIOFileSystem
#endif

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
    package struct FileBufferURL: BufferURL {

        // MARK: - Internal static properties

        /// A path inside the system temporary directory that nothing else holds.
        ///
        /// The file is not created here. Whoever writes first creates it, and the storage that
        /// owns this URL removes it when it goes away.
        package static var temporaryURL: Internals.FileBufferURL {
            let timestamp = Int(Date.timeIntervalSinceReferenceDate)
            let pathComponent = "\(timestamp).\(UUID().uuidString).buffer"
            let path = FilePath.temporaryDirectory.appending(pathComponent)

            return .init(path: path, url: URL(fileURLWithPath: path.string), isTemporary: true)
        }

        // MARK: - Internal properties

        /// The path the streams open against.
        ///
        /// - Important: Must be derived once, at init, not rebuilt from a `String` on every
        /// call, including inside the open path of both streams.
        package let path: FilePath

        /// - Important: This is a stat call, not a stored value.
        /// - Returns: Zero when the file is missing or unreadable, which is what an empty
        /// buffer looks like to everything upstream.
        package var writtenBytes: Int {
            get async {
                do {
                    guard let info = try await Internals.fileSystem.info(forFileAt: path) else {
                        return .zero
                    }

                    return Self.readableSize(ofFileSized: info.size)
                } catch {
                    return .zero
                }
            }
        }

        /// What a file of `size` bytes reports as its written bytes: its size, or zero when it
        /// cannot be counted in an `Int`.
        ///
        /// Not clamped: on a 32-bit platform (watchOS' `arm64_32`) a clamp would report `Int.max`
        /// for a file past 2 GiB, and whoever reads up to that count would stop at 2 GiB and end
        /// its stream as if the body were whole. Zero is what an unreadable file looks like to
        /// everything upstream: a buffer opened over it (`Internals.Buffer.init(addressing:)`,
        /// after waiting out the empty-content retry) is empty and its read ends at once, with no
        /// error. That would send a body of zero bytes in place of the file, so it must never be
        /// what a caller meets: what this package writes on a 32-bit platform is refused beforehand
        /// by `BufferBounds`, and a file of the caller's (`Payload(url:)`, `Form(... url:)`) past 2 GiB
        /// is refused by `FilePayloadFactory`, with a `FilePayloadError`, before a buffer is built over
        /// it. Only a file that grew past the limit after that check can still read as empty here.
        ///
        /// - Parameter limit: The largest size that is representable; only a test sets it, to
        ///   stand in for a 32-bit `Int` without a file of 2 GiB.
        static func readableSize(ofFileSized size: Int64, limit: Int = .max) -> Int {
            guard size >= .zero, size <= Int64(limit) else {
                return .zero
            }

            return Int(size)
        }

        // MARK: - Private properties

        private let url: URL
        /// Whether this location is one this package created for its own scratch use (and will
        /// remove once nothing needs it any more), as opposed to a caller-supplied path. See
        /// `Internals.Buffer.wholeFileURL`, the one external reader of this flag, for why the
        /// distinction matters outside this type.
        package let isTemporary: Bool

        // MARK: - Inits

        package init(_ url: URL) {
            self.init(path: url.filePath, url: url, isTemporary: false)
        }

        private init(path: FilePath, url: URL, isTemporary: Bool) {
            self.path = path
            self.url = url
            self.isTemporary = isTemporary
        }

        // MARK: - Internal static methods

        package static func make(from url: URL) -> Internals.FileBufferURL? {
            .init(url)
        }

        // MARK: - Internal methods

        package func isResourceAvailable() async -> Bool {
            await url.isReachable
        }

        /// - Important: Failures are swallowed. The open that follows reports the same problem
        /// with better context, and there is nothing useful to do here on the way past.
        package func createResourceIfNeeded() async {
            try? await url.createPathIfNeeded()
        }

        /// Empties the file.
        ///
        /// - Warning: This is allowed to replace the file rather than shorten it in place, so
        /// any descriptor already open against it may end up addressing an unlinked object.
        /// Callers close their streams first.
        package func truncate() async {
            guard await isResourceAvailable() else {
                return
            }

            do {
                let handle = try await Internals.fileSystem.openFile(
                    forWritingAt: path,
                    options: .newFile(replaceExisting: true, permissions: .ownerReadWrite)
                )

                try await Internals.uncancellable { try await handle.close() }
            } catch {}
        }

        /// Removes the file when this package created it.
        ///
        /// Runs through `Internals.uncancellable`: a request that is cancelled cleans up from a
        /// cancelled Task, where `NIOFileSystem` refuses the work with a `CancellationError` and
        /// the file would stay behind.
        package func removeIfTemporary() async {
            guard isTemporary else {
                return
            }

            let url = url
            try? await Internals.uncancellable { try await url.removeIfNeeded() }
        }

        package func absoluteURL() -> URL {
            url
        }
    }
}
