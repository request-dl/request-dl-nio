//
// See LICENSE for this package's licensing information.
//

// Only reachable once the future URLSession-only trait exists. NIOCore is always present today,
// so `#if !canImport(NIOCore)` never evaluates `true` in this build, and
// `swift build`/`swift test` never type-check this file.
// Verified correct by writing real `.gz` files from a standalone script and validating them with
// the system `gunzip -t` (byte-for-byte content check against a random binary payload too),
// since the normal test suite can't reach it yet. Same discipline as
// `PortableDeflateCompressorStream`, whose header/trailer-wrapping technique this mirrors.
//
// Gated on `canImport(zlib)` too (not just `!canImport(NIOCore)`): the `crc32()` trailer below is
// a genuine, narrower dependency on the `zlib` C library, separate from the NIOCore/Darwin
// question this whole effort otherwise turns on. `GzipAlgorithm` falls back to
// `CompressionUnavailableError` instead of failing to compile if `zlib` isn't importable.
#if !canImport(NIOCore) && canImport(zlib)

import Foundation
import zlib

/// Portable ``CompressorStream`` behind ``GzipAlgorithm`` when NIO isn't available, producing the
/// same wire format (`Content-Encoding: gzip`, i.e. an RFC 1952 gzip stream) that
/// ``NIOHTTPCompressorStreamBridge`` produces through `NIOHTTPRequestCompressor`, using only
/// Foundation + Apple's `Compression` framework instead: the gzip counterpart of
/// ``PortableDeflateCompressorStream``.
///
/// - Important: As with the zlib wrapper, `NSData.compressed(using: .zlib)` only ever hands back
///   **raw DEFLATE** (RFC 1951); see that type's own doc comment. Gzip's own container (RFC
///   1952) is a different wrapper around the same raw deflate bytes: a 10-byte header (magic
///   `0x1F 0x8B`, compression method `0x08`, no flags, zeroed mtime, unset extra flags, `0xFF`
///   for "OS unknown"; none of these are load-bearing for a decoder, they're metadata a
///   compliant reader ignores) followed by a little-endian CRC-32 of the *uncompressed* bytes and
///   a little-endian `UInt32` of the uncompressed size modulo 2^32 (`ISIZE`, per spec: not a bug
///   for bodies over 4 GiB, since decoders are required to handle the wraparound). Confirmed
///   correct by writing real `.gz` files and validating them with the system `gunzip -t` before
///   writing this, not assumed from the spec alone.
///
/// - Note: Same tradeoff as ``PortableDeflateCompressorStream``: buffers the entire body and
///   compresses once in ``finish()`` rather than streaming incrementally, since `Compression`'s
///   buffer-based API has no incremental entry point the way `NIOHTTPRequestCompressor` does.
///   Correct per ``CompressorStream``'s own doc comment (returning `[]` until `finish()` is
///   explicitly valid), just not memory-bounded for very large bodies. See that type's doc
///   comment for the same "revisit with `compression_stream`'s incremental C API" note.
struct PortableGzipCompressorStream: CompressorStream {

    // MARK: - Private properties

    private var buffer = Data()

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
        buffer.append(contentsOf: bytes)
        return []
    }

    mutating func finish() throws -> [UInt8] {
        var output = Data([
            0x1F, 0x8B,             // Magic number
            0x08,                   // CM: deflate
            0x00,                   // FLG: none set
            0x00, 0x00, 0x00, 0x00, // MTIME: unset
            0x00,                   // XFL: unset
            0xFF                    // OS: unknown
        ])
        output.append(try (buffer as NSData).compressed(using: .zlib) as Data)

        var crc = Self.crc32Checksum(of: buffer).littleEndian
        output.append(Data(bytes: &crc, count: MemoryLayout<UInt32>.size))

        var isize = UInt32(truncatingIfNeeded: buffer.count).littleEndian
        output.append(Data(bytes: &isize, count: MemoryLayout<UInt32>.size))

        return Array(output)
    }

    // MARK: - Private methods

    private static func crc32Checksum(of data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(crc32(0, buffer.baseAddress, UInt32(buffer.count)))
        }
    }
}

#endif
