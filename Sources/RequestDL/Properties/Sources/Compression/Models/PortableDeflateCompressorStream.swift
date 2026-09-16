//
// See LICENSE for this package's licensing information.
//

// Only reachable once the future URLSession-only trait exists (see `URLSESSION_ONLY_REPORT.md`
// at the repo root), NIOCore is always present today, so `#if !canImport(NIOCore)` never
// evaluates `true` in this build, and `swift build`/`swift test` never type-check this file.
// Verified correct by a standalone round-trip script against real zlib `inflate()` (multiple
// sizes including empty and random binary payloads) before writing this, since the normal test
// suite can't reach it yet.
//
// Gated on `canImport(zlib)` too (not just `!canImport(NIOCore)`): the `adler32()` trailer below
// is a genuine, narrower dependency on the `zlib` C library, separate from the NIOCore/Darwin
// question this whole effort otherwise turns on. `DeflateAlgorithm` falls back to
// `CompressionUnavailableError` instead of failing to compile if `zlib` isn't importable.
#if !canImport(NIOCore) && canImport(zlib)

import Foundation
import zlib

/// Portable ``CompressorStream`` behind ``DeflateAlgorithm`` when NIO isn't available, producing
/// the same wire format (`Content-Encoding: deflate`, i.e. an RFC 1950 zlib-wrapped deflate
/// stream) that ``NIOHTTPCompressorStreamBridge`` produces through `NIOHTTPRequestCompressor`,
/// using only Foundation + Apple's `Compression` framework instead.
///
/// - Important: `NSData.compressed(using: .zlib)` (backed by `COMPRESSION_ZLIB`) despite the name
///   produces **raw DEFLATE** (RFC 1951), not an actual RFC 1950 zlib stream: no header, no
///   trailer. Feeding the assembled output straight back into `NSData.decompressed(using: .zlib)`
///   fails for exactly that reason, confirmed while writing this, not assumed. The 2-byte header
///   below (`0x78, 0x5E`: CMF for a 32K window / deflate method, FLG chosen so the 16-bit pair is
///   a multiple of 31, no preset dictionary) plus the big-endian Adler-32 trailer are what turn
///   the raw deflate bytes into a real zlib stream any standard HTTP server's `inflate()` can
///   decode.
///
/// - Note: Unlike ``NIOHTTPCompressorStreamBridge`` (which feeds `NIOHTTPRequestCompressor`
///   incrementally, in bounded memory), this buffers the entire body and compresses it once in
///   ``finish()``, the `Compression` framework's buffer-based API has no incremental entry point
///   the way `NIOHTTPRequestCompressor` does. Returning `[]` from every
///   `callAsFunction(compressing:)` call is an explicitly valid ``CompressorStream``
///   implementation (see that protocol's own doc comment), so this is correct, just not
///   memory-bounded for very large bodies. Worth revisiting with `compression_stream`'s true
///   incremental C API if bounded memory ever becomes a real constraint for a shipped
///   URLSession-only build.
struct PortableDeflateCompressorStream: CompressorStream {

    // MARK: - Private properties

    private var buffer = Data()

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
        buffer.append(contentsOf: bytes)
        return []
    }

    mutating func finish() throws -> [UInt8] {
        var output = Data([0x78, 0x5E])
        output.append(try (buffer as NSData).compressed(using: .zlib) as Data)

        var checksum = Self.adler32Checksum(of: buffer).bigEndian
        output.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))

        return Array(output)
    }

    // MARK: - Private methods

    private static func adler32Checksum(of data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(adler32(1, buffer.baseAddress, UInt32(buffer.count)))
        }
    }
}

#endif
