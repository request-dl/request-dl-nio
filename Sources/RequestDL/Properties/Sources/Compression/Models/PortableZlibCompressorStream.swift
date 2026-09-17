//
// See LICENSE for this package's licensing information.
//

// Gated on `canImport(zlib)` alone, not also `!canImport(NIOCore)`. `DeflateAlgorithm` and
// `GzipAlgorithm` (this type's only callers, through `PortableDeflateCompressorStream` and
// `PortableGzipCompressorStream`) already decide which stream to hand back based on whether
// NIOCore is available, so this file doesn't need to repeat that condition to stay unused
// whenever NIO is around. Compiling it in every build, not just a future NIOCore-less one,
// lets the normal test suite exercise it directly instead of relying on a standalone script.
#if canImport(zlib)

import RequestDLInternals
import zlib

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Drives zlib's own incremental `deflate()` C API for genuinely streaming, bounded-memory
/// compression. It backs both ``PortableDeflateCompressorStream`` (RFC 1950 zlib wrapper) and
/// ``PortableGzipCompressorStream`` (RFC 1952 gzip wrapper), which differ only in the
/// `windowBits` passed to ``init(windowBits:)``. That also lets zlib generate the right
/// header, trailer and checksum itself, instead of hand-rolling a wrapper around Apple's
/// `Compression` framework.
///
/// - Note: `z_stream`'s `state` field is a zlib-owned, heap-allocated pointer for the lifetime
/// between `deflateInit2_` and `deflateEnd`. Wrapped in a `final class`, not held as a `struct`
/// value directly on ``PortableDeflateCompressorStream``/``PortableGzipCompressorStream``: a
/// Swift-level copy of a struct holding the `z_stream` value directly would copy that pointer
/// too, letting two independent-looking values alias the same zlib state and free it out from
/// under each other the moment either one's `finish()` runs `deflateEnd`. Same discipline
/// `ZeroingBytes` uses for its own manually-managed buffer.
final class PortableZlibCompressorStream: @unchecked Sendable {

    // MARK: - Private static properties

    /// zlib's own usage notes suggest a buffer "large enough" that most calls drain in one
    /// `deflate()` pass; 32 KiB is the size zlib's own `minigzip.c` example reaches for.
    private static let outputChunkSize = 32 * 1_024

    // MARK: - Private properties

    private var strm = z_stream()
    private var isOpen = true

    /// `drain(flush:)`'s own output buffer, held here instead of allocated fresh on every call:
    /// a stream gets one `compress(_:)` call per request body chunk, so a fresh, zero-filled
    /// 32 KiB buffer per call adds up to one allocation per chunk for the lifetime of an
    /// upload. Reusing this one is safe without re-zeroing it between calls: `drain(flush:)`
    /// only ever reads back the first `produced` bytes it just wrote (`chunk.prefix(produced)`),
    /// never whatever a previous call left past that point.
    private var chunk = Data(repeating: .zero, count: PortableZlibCompressorStream.outputChunkSize)

    // MARK: - Inits

    /// - Parameter windowBits: `15` for an RFC 1950 zlib stream, `15 + 16` for an RFC 1952 gzip
    /// stream, per zlib's own `deflateInit2` documentation.
    init(windowBits: Int32) throws {
        let result = deflateInit2_(
            &strm,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            windowBits,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )

        guard result == Z_OK else {
            throw PortableZlibError(code: result)
        }
    }

    deinit {
        if isOpen {
            deflateEnd(&strm)
        }
    }

    // MARK: - Internal methods

    /// Feeds `bytes` through `deflate(Z_NO_FLUSH)`, returning whatever compressed output zlib
    /// produced so far. May return empty `Data`: zlib is free to buffer internally until it has
    /// enough to emit a block, exactly as ``CompressorStream``'s own doc comment allows.
    ///
    /// - Note: `Data`, not `[UInt8]`. `PortableGzipCompressorStream` and
    /// `PortableDeflateCompressorStream` convert to and from `[UInt8]` at their own boundary,
    /// only because the public `Compressor` API they conform to is `[UInt8]`-based. Operating on
    /// `Data` here lets ``PortableZlibCompressorNativeStream`` drive this type straight from and
    /// back to `Internals.Bytes`, avoiding an `Internals.Bytes` ⇄ `[UInt8]` round trip on every
    /// chunk even though nothing outside this package ever touches it as `[UInt8]`.
    func compress(_ bytes: Data) throws -> Data {
        var bytes = bytes
        return try bytes.withUnsafeMutableBytes { (input: UnsafeMutableRawBufferPointer) in
            strm.next_in = input.bindMemory(to: UInt8.self).baseAddress
            strm.avail_in = UInt32(input.count)
            return try drain(flush: Z_NO_FLUSH)
        }
    }

    /// Flushes and closes the stream, returning the final compressed bytes (the last block plus
    /// the format's trailer). Must be called exactly once, after the last ``compress(_:)`` call.
    func finish() throws -> Data {
        defer {
            deflateEnd(&strm)
            isOpen = false
        }

        strm.next_in = nil
        strm.avail_in = .zero
        return try drain(flush: Z_FINISH)
    }

    // MARK: - Private methods

    /// Repeatedly calls `deflate`, each time into ``chunk``, until it comes back not full
    /// (`avail_out != 0`): zlib's own documented signal that it has produced everything it can
    /// for the current `avail_in`/`flush` combination. `strm.next_in`/`avail_in` must already be
    /// set by the caller; this only drives the output side.
    private func drain(flush: Int32) throws -> Data {
        var output = Data()

        repeat {
            let produced = try chunk.withUnsafeMutableBytes { (outBuffer: UnsafeMutableRawBufferPointer) -> Int in
                strm.next_out = outBuffer.bindMemory(to: UInt8.self).baseAddress
                strm.avail_out = UInt32(outBuffer.count)

                let result = deflate(&strm, flush)
                guard result != Z_STREAM_ERROR else {
                    throw PortableZlibError(code: result)
                }

                return outBuffer.count - Int(strm.avail_out)
            }

            output.append(chunk.prefix(produced))
        } while strm.avail_out == .zero

        return output
    }
}

/// The `Internals.Bytes`-native stream `PortableGzipCompressorStream`/
/// `PortableDeflateCompressorStream` bridge to the public, `[UInt8]`-based `CompressorStream`
/// through their own `nativeStream` property. `InternalsCompressionAlgorithmAdapter` reaches for
/// this directly instead of going through `callAsFunction(compressing:)`, so driving the portable
/// gzip/deflate compressors from inside the package skips the `[UInt8]` conversion entirely.
/// This mirrors `NIOHTTPCompressorStreamBridge.nativeStream`'s own reasoning, adapted to a
/// `Data`-based engine instead of a `ByteBuffer`-based one.
struct PortableZlibCompressorNativeStream: Internals.CompressorStream {

    // MARK: - Private properties

    private let stream: PortableZlibCompressorStream

    // MARK: - Inits

    init(stream: PortableZlibCompressorStream) {
        self.stream = stream
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: Internals.Bytes) throws -> Internals.Bytes {
        var bytes = bytes
        return Internals.Bytes(try stream.compress(bytes.asData()))
    }

    mutating func finish() throws -> Internals.Bytes {
        Internals.Bytes(try stream.finish())
    }
}

/// zlib reports failure through `deflateInit2_`/`deflate`'s return code rather than raising, and
/// this package doesn't silently ignore one. Practically unreachable: every parameter
/// ``PortableZlibCompressorStream`` passes zlib is a fixed, known-valid constant.
struct PortableZlibError: Error, Sendable {
    let code: Int32
}

#endif
