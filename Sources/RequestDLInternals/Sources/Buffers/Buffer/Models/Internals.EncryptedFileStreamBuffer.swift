//
// See LICENSE for this package's licensing information.
//

import Crypto
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

extension Internals {

    /// A stream over an AES-GCM encrypted file, chunked the way `age`/`libsodium.secretstream`
    /// chunk a STREAM-construction ciphertext: plaintext is sealed a fixed-size chunk at a time,
    /// each chunk independently authenticated, rather than as one whole-file blob.
    ///
    /// ## Why chunked, not whole-blob
    ///
    /// The response body this backs (`data.record`) is written incrementally as bytes arrive off
    /// the network — see `Internals.CacheControl.cacheIfNeeded` — specifically so the whole body
    /// never has to sit in memory at once. Whole-blob AES-GCM needs the entire plaintext before
    /// it can produce a tag, which would undo that. Chunking bounds memory to one chunk
    /// (`chunkPlaintextSize`) regardless of body size, and — because the real read path here is
    /// always forward-sequential, never sliced (confirmed in `DiskStorage`/`CacheControl`) —
    /// needs no genuine random access to pull off.
    ///
    /// ## On-disk layout
    ///
    /// ```
    /// [1 byte format version][12 byte random base nonce][chunk 0][chunk 1]...[chunk N, isLast]
    /// ```
    /// Every chunk but the last holds exactly `chunkPlaintextSize` plaintext bytes; the last
    /// holds whatever remains (0 when the body divides evenly — `close()` always flushes one
    /// final chunk, even an empty one, so the stream always ends with an authenticated
    /// `isLast=true` marker). Each chunk is `ciphertext (== its plaintext length) + 16 byte tag`
    /// — no per-chunk nonce is stored (`SealedBox.combined` is deliberately not used here): the
    /// nonce is derived, not carried.
    ///
    /// ## Nonce and associated data
    ///
    /// The nonce for chunk `i` is the base nonce with its last 8 bytes XORed against `i` as a
    /// big-endian `UInt64` — unique for the lifetime of one file without needing fresh randomness
    /// per chunk. The associated data authenticated alongside each chunk is `i` (big-endian,
    /// 8 bytes) followed by a 1-byte `isLast` flag. Binding both closes the gap chunking reopens
    /// relative to whole-blob encryption: without it, a chunk-level GCM tag check alone can't
    /// catch chunks being reordered, spliced in from a different file, or the trailing chunks
    /// being dropped to fake a shorter body — each remaining chunk still verifies fine on its
    /// own. With the index and finality authenticated, any of those changes what a chunk decrypts
    /// against, and the tag check fails.
    ///
    /// ## Where "is this the last chunk" comes from on read
    ///
    /// Position in the file, not a stored flag: the last on-disk block, whatever its size, is
    /// always attempted as final. By construction (see `writeData`'s flush loop), that block is
    /// always strictly shorter, on disk, than a full `chunkOnDiskSize` — so there's no ambiguity
    /// between "coincidentally full-size" and genuinely non-final. A writer that crashed before
    /// ever flushing its actual final, `isLast=true`-flagged chunk leaves the file's real last
    /// block flagged `isLast=false` at seal time; reading it back and asserting `isLast=true`
    /// (the read side's positional guess) produces the wrong associated data, the tag check
    /// fails, and the whole file degrades to a decrypt-failure/cache-miss — exactly the outcome
    /// wanted for a truncated write, with no special-case code.
    ///
    /// ## Append-only, by construction
    ///
    /// `writeData` only ever supports writing at the stream's own current end — see its doc for
    /// what happens otherwise. This is not a general-purpose random-access encrypted file; it is
    /// scoped tightly to how a cache entry is actually written and read.
    package final class EncryptedFileStreamBuffer: @unchecked Sendable, StreamBuffer {

        package typealias URL = Internals.EncryptedFileBufferURL

        // MARK: - Package static properties

        /// Plaintext bytes per non-final chunk. A few MB, matching the "accumulate a few MB,
        /// encrypt, flush" shape this format exists for — small enough to bound memory well
        /// below a large response body, large enough that the fixed 16 byte per-chunk tag
        /// overhead stays negligible.
        package static let chunkPlaintextSize = 4 * 1_024 * 1_024

        // MARK: - Private static properties

        private static let formatVersion: UInt8 = 0x01
        private static let baseNonceSize = 12
        private static let tagSize = 16
        private static let headerSize = 1 + baseNonceSize
        private static let chunkOnDiskSize = chunkPlaintextSize + tagSize

        /// Flags a seek/read/write/close still running after 15s. Development builds only,
        /// mirroring `Internals.FileStreamBuffer`'s identical watchdog.
        #if DEBUG
        private static let watchdog: AsyncLock.Watchdog? = .init(seconds: 15) {
            Internals.assertionFailure($0)
        }
        #else
        private static let watchdog: AsyncLock.Watchdog? = nil
        #endif

        // MARK: - Private types

        private enum Handle: Sendable {
            case read(Internals.FileStreamBuffer)
            case write(Internals.FileStreamBuffer)
        }

        private enum StreamError: Error {
            /// `writeData` was asked to write somewhere other than the stream's own current end.
            case nonSequentialWrite
            /// A chunk's on-disk framing doesn't hold together (too short to even carry a tag),
            /// distinct from a tag mismatch, which `Crypto` itself throws.
            case truncatedChunk
        }

        // MARK: - Internal properties

        package var offset: UInt64 {
            get async throws {
                await lock.withLock { _offset }
            }
        }

        // MARK: - Private properties

        private let lock = AsyncLock(watchdog: watchdog)
        private let handle: Handle
        private let key: SymmetricKey
        private let innerURL: Internals.FileBufferURL

        // MARK: - Unsafe write-side properties

        /// - Warning: Lockless. Only reachable from inside `lock`.
        private var _offset: UInt64 = .zero

        /// Plaintext bytes actually sealed-or-queued so far. The ground truth `writeData`
        /// validates `_offset` against — see its doc for why the two are not the same variable.
        private var _writtenPlaintextCount: UInt64 = .zero

        private var _pendingPlaintext = Data()
        private var _chunkIndex: UInt64 = .zero
        private var _baseNonce: Data?
        private var _headerWritten = false
        private var _isClosed = false

        // MARK: - Unsafe read-side properties

        /// - Warning: Lockless. Only reachable from inside `lock`.
        private var _cachedRawFileSize: UInt64?
        private var _cachedBaseNonce: Data?
        private var _cachedChunkIndex: UInt64?
        private var _cachedChunkPlaintext: Data?

        // MARK: - Inits

        package init(readingFrom url: URL) async throws {
            handle = .read(try await Internals.FileStreamBuffer(readingFrom: url.inner))
            key = url.key
            innerURL = url.inner
        }

        /// - Important: Assumes `url` addresses a fresh (nonexistent or empty) file, matching
        /// how `DiskStorage` actually uses this: every cache write targets a brand new `Record`
        /// directory, never an existing `data.record` being appended to across sessions.
        /// Resuming a partially written encrypted file is out of scope.
        package init(writingTo url: URL) async throws {
            handle = .write(try await Internals.FileStreamBuffer(writingTo: url.inner))
            key = url.key
            innerURL = url.inner
        }

        // MARK: - Internal methods

        /// Moves the offset the next operation will address.
        ///
        /// Recorded, not validated here — `writeData` is what rejects a write to anywhere other
        /// than the stream's current end. This mirrors `Internals.FileStreamBuffer.seek`: cheap,
        /// never fails on its own.
        package func seek(to offset: UInt64) async throws {
            await lock.withLock { _offset = offset }
        }

        /// Appends `data` at the stream's own current end, chunking and sealing as the pending
        /// buffer crosses `chunkPlaintextSize`.
        ///
        /// - Important: Only supports writing at the stream's current end. Every real write
        /// against a cache entry's `data.record` already lands there — `Internals.Buffer.Storage
        /// .write(at:data:)` always seeks to its own tracked writer index immediately before
        /// writing, and that index only ever advances by what was actually written. A write
        /// elsewhere would mean rewriting an already-sealed chunk, which needs a genuine
        /// read-modify-reseal this type deliberately does not support (see the type-level doc):
        /// it throws instead, which `Internals.Buffer.Storage.write`'s existing
        /// `catch { return index }` already turns into an ordinary, silent write failure — the
        /// same shape every other write failure in this subsystem already has.
        package func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async throws {
            let incoming = Data(data)

            guard !incoming.isEmpty else {
                return
            }

            guard case .write(let writeStream) = handle else {
                return
            }

            try await lock.withLock {
                guard _offset == _writtenPlaintextCount else {
                    throw StreamError.nonSequentialWrite
                }

                if !_headerWritten {
                    try await writeHeader(writeStream)
                }

                _pendingPlaintext.append(incoming)
                _writtenPlaintextCount += UInt64(incoming.count)
                _offset = _writtenPlaintextCount

                while _pendingPlaintext.count >= Self.chunkPlaintextSize {
                    let chunk = _pendingPlaintext.prefix(Self.chunkPlaintextSize)
                    try await seal(chunk, isLast: false, to: writeStream)
                    _pendingPlaintext.removeFirst(Self.chunkPlaintextSize)
                }
            }
        }

        /// Reads up to `length` plaintext bytes forward from `_offset`, decrypting whichever
        /// chunks that range spans.
        ///
        /// - Returns: `nil` at EOF (including every corruption/tamper/wrong-key case — a failed
        /// chunk decrypt throws from inside the loop below, which
        /// `Internals.Buffer.Storage.read`'s existing `catch { return (nil, index) }` turns into
        /// an ordinary read failure, indistinguishable from EOF to everything above this type).
        package func readData(length: UInt64) async throws -> Data? {
            guard length > .zero else {
                return nil
            }

            guard case .read(let readStream) = handle else {
                return nil
            }

            return try await lock.withLock { () async throws -> Data? in
                var result = Data()
                var remaining = length

                while remaining > .zero {
                    let chunkIndex = _offset / UInt64(Self.chunkPlaintextSize)
                    let intraChunkOffset = Int(_offset % UInt64(Self.chunkPlaintextSize))

                    guard let plaintext = try await decryptedChunk(at: chunkIndex, using: readStream) else {
                        break
                    }

                    guard intraChunkOffset < plaintext.count else {
                        break
                    }

                    let available = UInt64(plaintext.count - intraChunkOffset)
                    let toTake = min(available, remaining)

                    let start = plaintext.index(plaintext.startIndex, offsetBy: intraChunkOffset)
                    let end = plaintext.index(start, offsetBy: Int(toTake))
                    result.append(plaintext[start..<end])

                    _offset += toTake
                    remaining -= toTake
                }

                guard !result.isEmpty else {
                    return nil
                }

                return result
            }
        }

        /// - Note: Closing twice is a no op. Idempotent for the same reason
        /// `Internals.FileStreamBuffer.close()` is: the storage detaches its streams before
        /// closing them, so this should not happen, but a redundant call is far cheaper than
        /// closing an already-closed handle.
        ///
        /// - Important: On the write side, this is the only place the final (`isLast=true`)
        /// chunk is flushed — including the empty final chunk a fully chunk-aligned body still
        /// needs, so every encrypted `data.record` always terminates with an authenticated
        /// finality marker. `Internals.Buffer.Storage`'s `deinit`-triggered detached task is
        /// confirmed to be the only place this is guaranteed to run for a cache write today (no
        /// explicit `.close()` follows the network-draining loop in
        /// `Internals.CacheControl.cacheIfNeeded`); a process that dies before that task runs
        /// simply never gets a final chunk, which the read side already treats as a decrypt
        /// failure, not corruption that needs special handling.
        package func close() async throws {
            try await lock.withLock {
                guard !_isClosed else {
                    return
                }

                _isClosed = true

                switch handle {
                case .read(let readStream):
                    try await readStream.close()
                case .write(let writeStream):
                    if !_headerWritten {
                        try await writeHeader(writeStream)
                    }

                    try await seal(_pendingPlaintext, isLast: true, to: writeStream)
                    _pendingPlaintext.removeAll()

                    try await writeStream.close()
                }
            }
        }

        // MARK: - Package static methods

        /// The logical plaintext size a raw (ciphertext) file of `rawSize` bytes holds, computed
        /// without decrypting anything — pure arithmetic over the fixed header/chunk/tag sizes.
        /// See ``Internals/EncryptedFileBufferURL``'s `writtenBytes` for why this has to be exact.
        package static func plaintextSize(fromRawSize rawSize: Int) -> Int {
            guard rawSize > headerSize else {
                return .zero
            }

            let body = rawSize - headerSize

            guard body > .zero else {
                return .zero
            }

            let fullNonFinalChunks = (body - 1) / chunkOnDiskSize
            let lastChunkOnDiskSize = body - fullNonFinalChunks * chunkOnDiskSize
            let lastChunkPlaintext = max(0, lastChunkOnDiskSize - tagSize)

            return fullNonFinalChunks * chunkPlaintextSize + lastChunkPlaintext
        }

        // MARK: - Private methods

        /// Writes the 13 byte header — format version plus a fresh random base nonce — once, at
        /// the very start of the file.
        private func writeHeader(_ stream: Internals.FileStreamBuffer) async throws {
            let baseNonce = Data(AES.GCM.Nonce())
            _baseNonce = baseNonce

            var header = Data([Self.formatVersion])
            header.append(baseNonce)

            try await stream.seek(to: .zero)
            try await stream.writeData(header)
            _headerWritten = true
        }

        /// Seals `plaintext` as chunk `_chunkIndex` and appends `ciphertext + tag` to `stream`,
        /// then advances `_chunkIndex`. Relies on `stream`'s own offset already sitting right
        /// after whatever was written before this call — the header, or the previous chunk —
        /// since nothing here ever seeks the inner stream mid-file.
        private func seal(_ plaintext: Data, isLast: Bool, to stream: Internals.FileStreamBuffer) async throws {
            guard let baseNonce = _baseNonce else {
                throw StreamError.truncatedChunk
            }

            let nonce = try Self.nonce(base: baseNonce, chunkIndex: _chunkIndex)
            let aad = Self.associatedData(chunkIndex: _chunkIndex, isLast: isLast)
            let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)

            var payload = sealedBox.ciphertext
            payload.append(sealedBox.tag)

            try await stream.writeData(payload)
            _chunkIndex += 1
        }

        /// Decrypts chunk `index`, caching the single most recently decrypted chunk — real usage
        /// is strictly forward-sequential, so successive `readData` calls landing inside the same
        /// chunk are the common case this avoids re-decrypting for.
        private func decryptedChunk(at index: UInt64, using stream: Internals.FileStreamBuffer) async throws -> Data? {
            if _cachedChunkIndex == index, let cached = _cachedChunkPlaintext {
                return cached
            }

            let rawSize = try await rawFileSize()

            guard rawSize > UInt64(Self.headerSize) else {
                return nil
            }

            let baseNonce = try await baseNonce(using: stream)

            let chunkStart = UInt64(Self.headerSize) + index * UInt64(Self.chunkOnDiskSize)

            guard chunkStart < rawSize else {
                return nil
            }

            let remainingInFile = rawSize - chunkStart
            let onDiskSize = min(remainingInFile, UInt64(Self.chunkOnDiskSize))
            let isLast = chunkStart + onDiskSize == rawSize

            guard onDiskSize > UInt64(Self.tagSize) else {
                throw StreamError.truncatedChunk
            }

            try await stream.seek(to: chunkStart)

            guard
                let raw = try await stream.readData(length: onDiskSize),
                UInt64(raw.count) == onDiskSize
            else {
                throw StreamError.truncatedChunk
            }

            let ciphertext = raw.prefix(Int(onDiskSize) - Self.tagSize)
            let tag = raw.suffix(Self.tagSize)

            let nonce = try Self.nonce(base: baseNonce, chunkIndex: index)
            let aad = Self.associatedData(chunkIndex: index, isLast: isLast)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let plaintext = try AES.GCM.open(sealedBox, using: key, authenticating: aad)

            _cachedChunkIndex = index
            _cachedChunkPlaintext = plaintext

            return plaintext
        }

        /// The random base nonce from the file's own 13 byte header, read and cached once.
        private func baseNonce(using stream: Internals.FileStreamBuffer) async throws -> Data {
            if let cached = _cachedBaseNonce {
                return cached
            }

            try await stream.seek(to: 1)

            guard
                let bytes = try await stream.readData(length: UInt64(Self.baseNonceSize)),
                bytes.count == Self.baseNonceSize
            else {
                throw StreamError.truncatedChunk
            }

            _cachedBaseNonce = bytes
            return bytes
        }

        /// The real on-disk (ciphertext) file size, stat'd and cached once. Safe to cache for a
        /// stream's whole lifetime: a cache entry's `data.record` is never mutated after it's
        /// fully written — `updateCached` creates a fresh `Record` rather than appending to an
        /// existing one — so nothing changes the raw size out from under a live read stream.
        private func rawFileSize() async throws -> UInt64 {
            if let cached = _cachedRawFileSize {
                return cached
            }

            let size = UInt64(await innerURL.writtenBytes)
            _cachedRawFileSize = size
            return size
        }

        /// Chunk `chunkIndex`'s nonce: the base nonce with its last 8 bytes XORed against the
        /// index as a big-endian `UInt64`. See the type-level doc for why counter-derived rather
        /// than fresh-random-per-chunk.
        private static func nonce(base: Data, chunkIndex: UInt64) throws -> AES.GCM.Nonce {
            var bytes = [UInt8](base)
            let counterBytes = withUnsafeBytes(of: chunkIndex.bigEndian) { Array($0) }

            for index in 0..<counterBytes.count {
                bytes[bytes.count - counterBytes.count + index] ^= counterBytes[index]
            }

            return try AES.GCM.Nonce(data: bytes)
        }

        /// The associated data authenticated alongside chunk `chunkIndex`: the index itself
        /// (big-endian, 8 bytes) followed by a 1 byte finality flag. See the type-level doc for
        /// why this is what catches reordering, splicing, and truncation.
        private static func associatedData(chunkIndex: UInt64, isLast: Bool) -> Data {
            var data = Data(withUnsafeBytes(of: chunkIndex.bigEndian) { Array($0) })
            data.append(isLast ? 0x01 : 0x00)
            return data
        }
    }
}
