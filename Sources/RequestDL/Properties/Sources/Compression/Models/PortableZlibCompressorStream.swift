//
// See LICENSE for this package's licensing information.
//

// Gated on `canImport(zlib)` alone, not also `!canImport(NIOCore)`: `DeflateAlgorithm`/
// `GzipAlgorithm` (this type's only callers, through `PortableDeflateCompressorStream`/
// `PortableGzipCompressorStream`) already decide which stream to hand back based on whether
// NIOCore is available, so this file doesn't need to repeat that condition to stay unused
// whenever NIO is around. Compiling it in every build, not just a future NIOCore-less one, is
// what lets the normal test suite actually exercise it, rather than relying on a standalone
// verification script the way the two callers' history did before this file existed.
#if canImport(zlib)

import zlib

/// Drives zlib's own incremental `deflate()` C API: genuinely streaming, bounded-memory
/// compression, backing both ``PortableDeflateCompressorStream`` (RFC 1950 zlib wrapper) and
/// ``PortableGzipCompressorStream`` (RFC 1952 gzip wrapper) — the two differ only in the
/// `windowBits` passed to ``init(windowBits:)``, which also makes zlib generate the right
/// header/trailer/checksum itself, unlike the `Compression`-framework-plus-hand-rolled-wrapper
/// approach this replaces.
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
    /// produced so far. May return an empty array: zlib is free to buffer internally until it
    /// has enough to emit a block, exactly as ``CompressorStream``'s own doc comment allows.
    func compress(_ bytes: [UInt8]) throws -> [UInt8] {
        var bytes = bytes
        return try bytes.withUnsafeMutableBufferPointer { input in
            strm.next_in = input.baseAddress
            strm.avail_in = UInt32(input.count)
            return try drain(flush: Z_NO_FLUSH)
        }
    }

    /// Flushes and closes the stream, returning the final compressed bytes (the last block plus
    /// the format's trailer). Must be called exactly once, after the last ``compress(_:)`` call.
    func finish() throws -> [UInt8] {
        defer {
            deflateEnd(&strm)
            isOpen = false
        }

        strm.next_in = nil
        strm.avail_in = .zero
        return try drain(flush: Z_FINISH)
    }

    // MARK: - Private methods

    /// Repeatedly calls `deflate`, each time into a fresh, empty output buffer, until it comes
    /// back not full (`avail_out != 0`): zlib's own documented signal that it has produced
    /// everything it can for the current `avail_in`/`flush` combination. `strm.next_in`/
    /// `avail_in` must already be set by the caller; this only drives the output side.
    private func drain(flush: Int32) throws -> [UInt8] {
        var output = [UInt8]()
        var chunk = [UInt8](repeating: .zero, count: Self.outputChunkSize)

        repeat {
            let produced = try chunk.withUnsafeMutableBufferPointer { outBuffer -> Int in
                strm.next_out = outBuffer.baseAddress
                strm.avail_out = UInt32(outBuffer.count)

                let result = deflate(&strm, flush)
                guard result != Z_STREAM_ERROR else {
                    throw PortableZlibError(code: result)
                }

                return outBuffer.count - Int(strm.avail_out)
            }

            output.append(contentsOf: chunk.prefix(produced))
        } while strm.avail_out == .zero

        return output
    }
}

/// zlib reports failure through `deflateInit2_`/`deflate`'s return code rather than raising, and
/// this package doesn't silently ignore one. Practically unreachable: every parameter
/// ``PortableZlibCompressorStream`` passes zlib is a fixed, known-valid constant.
struct PortableZlibError: Error, Sendable {
    let code: Int32
}

#endif
