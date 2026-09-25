//
// See LICENSE for this package's licensing information.
//

// Only reachable with the `NIOTransport` trait disabled. `#if !canImport(NIOCore)` never
// evaluates `true` under the default build, since NIOCore is present by default; it does under
// `swift build --disable-default-traits`, which the "URLSession-only Build" CI job
// (`.github/workflows/swift-ci.yaml`) runs on every push, type-checking this file for real.
#if !canImport(NIOCore)

import Foundation
import SystemPackage

extension Internals {

    /// `NIOFileSystem.FileSystem`'s counterpart without NIO: the same handful of operations
    /// `Internals.fileSystem` is actually called with across this package, backed by
    /// `FileManager`/`FileHandle` instead, every blocking call routed through
    /// `Internals.FileSystemManager.run` so it never runs on whichever Swift Concurrency
    /// cooperative thread happens to call in here. See that type's own doc comment for why that
    /// distinction matters under `swift-testing`'s parallel execution.
    ///
    /// Deliberately narrow: this mirrors the subset of `NIOFileSystem.FileSystem`'s API this
    /// package actually calls (`info`, `createDirectory`, `openFile` read/write,
    /// `removeItem`, `moveItem`, `withDirectoryHandle`), matching call-site syntax
    /// (`.newFile(replaceExisting:permissions:)`, `.bytes(_:)`, `.unlimited`, `entry.name.string`, …)
    /// closely enough that most call sites in `FileBufferURL`/`FileStreamBuffer`/
    /// `URL+Extensions.swift`/`DiskStorage.swift` compile completely unchanged against
    /// whichever of the two types `Internals.fileSystem` resolves to, not a general-purpose
    /// file system abstraction.
    package enum PortableFileSystem {

        // MARK: - Internal types

        /// Counterpart to `NIOFileSystem.FileInfo`, narrowed to the one field this package reads
        /// off it (`.size`).
        package struct Info: Sendable {
            package let size: Int64
        }

        /// Counterpart to `NIOFileSystem.OpenOptions.Write`, narrowed to the two cases this
        /// package actually constructs. Both cases' `permissions` take the same
        /// `SystemPackage.FilePermissions` `NIOFileSystem` itself takes (portable already, no
        /// NIO needed), matching call-site syntax (`.ownerReadWrite`) exactly rather than
        /// introducing a parallel type. (Caught by the force-compiled verification pass missing
        /// this parameter entirely on the first attempt:
        /// `Internals.FileStreamBuffer.init(writingTo:)` passes it unconditionally.)
        ///
        /// - Important: `.newFile`'s `permissions` has no default, unlike
        /// `NIOFileSystem.OpenOptions.Write.newFile(replaceExisting:permissions:)`'s own
        /// `permissions: FilePermissions? = nil` (which falls back to
        /// `.defaultsForRegularFile`, i.e. world-readable). Every call site on the NIO path must
        /// already pass `.ownerReadWrite` explicitly for the two backends to agree, so requiring
        /// it here too, rather than silently defaulting, keeps a future call site honest instead
        /// of letting it compile its way into the same gap `.newFile` on the NIO side otherwise
        /// invites.
        package enum WriteOptions: Sendable {
            /// Creates a fresh, empty file. Errors if one is already there and
            /// `replaceExisting` is `false` (`NIOFileSystem`'s own contract for this case),
            /// unlike `.modifyFile` below, which is silent about an existing file by design.
            case newFile(replaceExisting: Bool, permissions: FilePermissions)
            /// Opens an existing file untouched, only creating one that is missing.
            case modifyFile(createIfNecessary: Bool, permissions: FilePermissions)
        }

        /// Counterpart to the `ByteCount` `readChunk(fromAbsoluteOffset:length:)` takes,
        /// narrowed to the one case (`.bytes(_:)`) this package ever constructs.
        package enum ReadLength: Sendable {
            case bytes(Int64)
        }

        /// Counterpart to the `ByteCount` `readToEnd(maximumSizeAllowed:)` takes, narrowed to
        /// the one case (`.unlimited`) this package ever passes: nothing here enforces a cap,
        /// same as passing `.unlimited` on the NIOFileSystem side does not either.
        package enum ReadLimit: Sendable {
            case unlimited
        }

        /// Counterpart to the `ByteBuffer` `readChunk(fromAbsoluteOffset:length:)` returns,
        /// narrowed to the two members `Internals.FileStreamBuffer.readData(length:)` reads off
        /// it (`.readableBytes`/`.readableBytesView`), so that method's short-read loop compiles
        /// unchanged against either backend.
        ///
        /// `readableBytesView` is `Data`, not `[UInt8]`: the one call site only ever hands it to
        /// `Data.append(contentsOf:)`, which `Data` itself already satisfies as a `Sequence`, so
        /// there is no need to pay for an `Array` copy of every chunk read just to match
        /// `ByteBufferView`'s name.
        package struct Chunk: Sendable {
            package let readableBytes: Int
            package let readableBytesView: Data

            fileprivate init(_ data: Data) {
                readableBytes = data.count
                readableBytesView = data
            }
        }

        /// A file opened for reading. Every call offloads through
        /// `Internals.FileSystemManager.run`; nothing here touches `fileHandle` from any other
        /// thread.
        package struct ReadHandle: Sendable {

            fileprivate let fileHandle: FileHandle

            /// - Note: Loops over `FileHandle.read(upToCount:)` internally, inside the single
            /// `Internals.FileSystemManager.run` dispatch, until either `requested` bytes have
            /// been read or a read comes back empty (EOF). `read(upToCount:)` is free to return
            /// fewer bytes than asked without that meaning EOF, and `Internals.FileStreamBuffer
            /// .readData(length:)`'s own short-read loop calls back in here for whatever is
            /// still missing. Leaving that loop to drive every retry would pay a fresh
            /// continuation + `DispatchQueue.global` hop per short read instead of one for the
            /// whole logical read. Matches ``WriteHandle/write(contentsOf:toAbsoluteOffset:)``'s
            /// own already-loops-internally behavior on the write side (there, courtesy of
            /// `FileHandle.write(contentsOf:)` itself).
            package func readChunk(
                fromAbsoluteOffset offset: Int64,
                length: ReadLength
            ) async throws -> Chunk {
                let requested: Int64
                switch length {
                case .bytes(let value):
                    requested = value
                }

                return try await Internals.FileSystemManager.run {
                    try fileHandle.seek(toOffset: UInt64(offset))

                    var data = Data()

                    while data.count < requested {
                        guard
                            let next = try fileHandle.read(upToCount: Int(requested) - data.count),
                            !next.isEmpty
                        else {
                            break
                        }

                        data.append(next)
                    }

                    return Chunk(data)
                }
            }

            package func readToEnd(maximumSizeAllowed: ReadLimit) async throws -> Data {
                try await Internals.FileSystemManager.run {
                    try fileHandle.seek(toOffset: .zero)
                    return try fileHandle.readToEnd() ?? Data()
                }
            }

            package func close() async throws {
                try await Internals.FileSystemManager.run {
                    try fileHandle.close()
                }
            }
        }

        /// A file opened for writing. Same threading discipline as `ReadHandle`.
        package struct WriteHandle: Sendable {

            fileprivate let fileHandle: FileHandle

            /// - Returns: The number of bytes written. Always the full count: unlike a raw
            /// `write(2)`, `FileHandle.write(contentsOf:)` already loops internally over a short
            /// write rather than surfacing one, so there is nothing partial to report here. The
            /// short-write retry loop in `Internals.FileStreamBuffer.writeData(_:)` still runs
            /// correctly against this; it simply never has to loop more than once in practice.
            @discardableResult
            package func write<Bytes: DataProtocol & Sendable>(
                contentsOf data: Bytes,
                toAbsoluteOffset offset: Int64
            ) async throws -> Int64 {
                let payload = Data(data)

                return try await Internals.FileSystemManager.run {
                    try fileHandle.seek(toOffset: UInt64(offset))
                    try fileHandle.write(contentsOf: payload)
                    return Int64(payload.count)
                }
            }

            package func close() async throws {
                try await Internals.FileSystemManager.run {
                    try fileHandle.close()
                }
            }
        }

        /// One entry read back from `withDirectoryHandle(atPath:_:)`. `name` mirrors
        /// `NIOFileSystem`'s own two-level shape (`entry.name.string`) rather than exposing a
        /// plain `String`, so `DiskStorage.records()`'s `entry.name.string.hasSuffix(...)` call
        /// compiles unchanged against either backend.
        package struct DirectoryEntry: Sendable {
            package struct Name: Sendable {
                package let string: String
            }

            package let name: Name
        }

        /// Handed to `withDirectoryHandle(atPath:_:)`'s closure. The listing itself already ran
        /// by the time this exists. See that method's doc comment for why a snapshot is fine
        /// here.
        package struct DirectoryHandle: Sendable {

            fileprivate let entries: [DirectoryEntry]

            /// `AsyncThrowingStream`, not a plain `AsyncStream`, purely so `for try await entry
            /// in dir.listContents()` at the call site stays valid Swift regardless of which
            /// backend is active: this particular listing can't actually fail once it already
            /// has a `DirectoryHandle` in hand, since the enumeration happened up front in
            /// `withDirectoryHandle(atPath:_:)`.
            package func listContents() -> AsyncThrowingStream<DirectoryEntry, Error> {
                AsyncThrowingStream { continuation in
                    for entry in entries {
                        continuation.yield(entry)
                    }
                    continuation.finish()
                }
            }
        }

        // MARK: - Errors

        /// Thrown by `openFile(forWritingAt:options:)` for `.newFile(replaceExisting: false)`
        /// against a path that already has something there (`NIOFileSystem`'s own contract for
        /// that combination, not a silent open-the-existing-file fallback).
        package struct FileAlreadyExistsError: Error, Sendable {
            package let path: String
        }

        /// Thrown by `openFile(forWritingAt:options:)` for `.modifyFile(createIfNecessary:
        /// false)` against a path with nothing there.
        package struct FileNotFoundError: Error, Sendable {
            package let path: String
        }

        /// Thrown when `FileHandle`'s own failable initializer returns `nil`: a path that
        /// exists but couldn't actually be opened (permissions, a directory where a file was
        /// expected, and similar).
        package struct FileHandleOpenError: Error, Sendable {
            package let path: String
        }

        // MARK: - Internal static methods

        /// - Returns: `nil` for a missing file. A genuine I/O error (a permission problem, for
        /// instance) is folded into `nil` too, rather than propagated (a simplification versus
        /// `NIOFileSystem`'s own `info(forFileAt:)`), acceptable because every call site in this
        /// package already wraps this in its own `try?` or treats a miss as "empty"/"absent"
        /// regardless of cause.
        package static func info(forFileAt path: FilePath) async throws -> Info? {
            try await Internals.FileSystemManager.run {
                guard
                    let attributes = try? FileManager.default.attributesOfItem(atPath: path.string),
                    let size = attributes[.size] as? Int
                else {
                    return nil
                }

                return Info(size: Int64(size))
            }
        }

        package static func createDirectory(
            at path: FilePath,
            withIntermediateDirectories: Bool
        ) async throws {
            try await Internals.FileSystemManager.run {
                try FileManager.default.createDirectory(
                    atPath: path.string,
                    withIntermediateDirectories: withIntermediateDirectories
                )
            }
        }

        package static func openFile(forReadingAt path: FilePath) async throws -> ReadHandle {
            try await Internals.FileSystemManager.run {
                guard let fileHandle = FileHandle(forReadingAtPath: path.string) else {
                    throw FileHandleOpenError(path: path.string)
                }

                return ReadHandle(fileHandle: fileHandle)
            }
        }

        package static func openFile(
            forWritingAt path: FilePath,
            options: WriteOptions
        ) async throws -> WriteHandle {
            try await Internals.FileSystemManager.run {
                let exists = FileManager.default.fileExists(atPath: path.string)

                switch options {
                case .newFile(let replaceExisting, let permissions):
                    guard replaceExisting else {
                        // `fileExists` + a separate `createFile` below is a check-then-act pair:
                        // two callers racing to create the same path could both pass that check
                        // and both call `createFile`, and since `createFile` overwrites
                        // unconditionally regardless of what the check saw, the loser would
                        // silently clobber the winner's just-written content instead of the
                        // `FileAlreadyExistsError` this case documents. `O_CREAT | O_EXCL` makes
                        // the create-if-absent decision and the creation itself one atomic
                        // syscall, so this returns straight from the exclusively-opened
                        // descriptor rather than falling through to the shared `FileHandle
                        // (forWritingAtPath:)` open below, which takes a path back to a second,
                        // ordinary (non-exclusive) open.
                        do {
                            let descriptor = try FileDescriptor.open(
                                path,
                                .writeOnly,
                                options: [.create, .exclusiveCreate],
                                permissions: permissions
                            )

                            return WriteHandle(
                                fileHandle: FileHandle(fileDescriptor: descriptor.rawValue, closeOnDealloc: true)
                            )
                        } catch Errno.fileExists {
                            throw FileAlreadyExistsError(path: path.string)
                        }
                    }

                    guard
                        FileManager.default.createFile(
                            atPath: path.string,
                            contents: nil,
                            attributes: [.posixPermissions: permissions.rawValue]
                        )
                    else {
                        throw FileHandleOpenError(path: path.string)
                    }
                case .modifyFile(let createIfNecessary, let permissions):
                    guard exists || createIfNecessary else {
                        throw FileNotFoundError(path: path.string)
                    }

                    if !exists {
                        guard
                            FileManager.default.createFile(
                                atPath: path.string,
                                contents: nil,
                                attributes: [.posixPermissions: permissions.rawValue]
                            )
                        else {
                            throw FileHandleOpenError(path: path.string)
                        }
                    }
                }

                guard let fileHandle = FileHandle(forWritingAtPath: path.string) else {
                    throw FileHandleOpenError(path: path.string)
                }

                return WriteHandle(fileHandle: fileHandle)
            }
        }

        package static func removeItem(at path: FilePath) async throws {
            try await Internals.FileSystemManager.run {
                try FileManager.default.removeItem(atPath: path.string)
            }
        }

        package static func moveItem(at source: FilePath, to destination: FilePath) async throws {
            try await Internals.FileSystemManager.run {
                try FileManager.default.moveItem(atPath: source.string, toPath: destination.string)
            }
        }

        /// Unlike `NIOFileSystem`'s own streaming directory iterator, this enumerates the whole
        /// directory up front (`FileManager.contentsOfDirectory(atPath:)`) and hands the closure
        /// a fixed snapshot: acceptable because every caller in this package (`DiskStorage
        /// .records()`) already reads a directory that is, at most, a few thousand cache entries,
        /// never a directory large enough for eager enumeration to matter.
        package static func withDirectoryHandle<T: Sendable>(
            atPath path: FilePath,
            _ body: (DirectoryHandle) async throws -> T
        ) async throws -> T {
            let entries = try await Internals.FileSystemManager.run { () throws -> [DirectoryEntry] in
                try FileManager.default.contentsOfDirectory(atPath: path.string).map {
                    DirectoryEntry(name: .init(string: $0))
                }
            }

            return try await body(DirectoryHandle(entries: entries))
        }
    }
}

#endif
