//
// See LICENSE for this package's licensing information.
//

// `import zlib` (and every type under test here) only exists where `canImport(zlib)` holds, same
// gate `PortableZlibCompressorStream` itself uses. That's `true` on every Apple platform (the SDK
// ships a module map for it) but not on Linux without a dedicated system-library target this
// package doesn't declare, so this file has to stay out of the Linux build entirely rather than
// just relying on the source side's own guard.
#if canImport(zlib)

import Testing
import zlib

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Round-trips `PortableZlibCompressorStream`'s output back through zlib's own incremental
/// `inflate()` — the authoritative decoder for both the RFC 1950 (`windowBits: 15`) and RFC 1952
/// (`windowBits: 15 + 16`) wire formats `PortableDeflateCompressorStream`/
/// `PortableGzipCompressorStream` produce. Previously this whole subsystem was gated on
/// `!canImport(NIOCore)`, so nothing here ever type-checked under the normal test suite; it's
/// only verified by a standalone script. `PortableZlibCompressorStream` itself is gated on
/// `canImport(zlib)` alone (see its own doc comment), so this suite runs for real, every time.
struct PortableZlibCompressorStreamTests {

    // MARK: - Private methods

    /// Decompresses `compressed` with zlib's own `inflate()`, using the same `windowBits`
    /// `compress(windowBits:chunks:)` encoded with, and asserts the exact bytes come back.
    private func decompress(windowBits: Int32, _ compressed: [UInt8]) -> [UInt8] {
        var strm = z_stream()
        let initResult = inflateInit2_(
            &strm,
            windowBits,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        #expect(initResult == Z_OK)
        defer { inflateEnd(&strm) }

        var output = [UInt8]()
        var outChunk = [UInt8](repeating: .zero, count: 16)
        var input = compressed

        input.withUnsafeMutableBufferPointer { inBuffer in
            strm.next_in = inBuffer.baseAddress
            strm.avail_in = UInt32(inBuffer.count)

            var result: Int32 = Z_OK
            repeat {
                let produced = outChunk.withUnsafeMutableBufferPointer { outBuffer -> Int in
                    strm.next_out = outBuffer.baseAddress
                    strm.avail_out = UInt32(outBuffer.count)
                    result = inflate(&strm, Z_NO_FLUSH)
                    #expect(result != Z_STREAM_ERROR)
                    #expect(result != Z_DATA_ERROR)
                    return outBuffer.count - Int(strm.avail_out)
                }
                output.append(contentsOf: outChunk.prefix(produced))
            } while result != Z_STREAM_END
        }

        return output
    }

    /// Drives `stream` the same way `InternalsCompressorStreamAdapter` does: several
    /// `compress(_:)` calls, then exactly one `finish()`.
    private func compress(
        windowBits: Int32,
        chunks: [[UInt8]]
    ) throws -> [UInt8] {
        let stream = try PortableZlibCompressorStream(windowBits: windowBits)

        var output = Data()
        for chunk in chunks {
            output += try stream.compress(Data(chunk))
        }
        output += try stream.finish()

        return Array(output)
    }

    // MARK: - Tests

    @Test
    func compress_whenZlibWindowBits_roundTripsThroughZlibsOwnInflate() throws {
        // Given
        let original = Array("The quick brown fox jumps over the lazy dog.".utf8)

        // When
        let compressed = try compress(windowBits: 15, chunks: [original])

        // Then
        #expect(decompress(windowBits: 15, compressed) == original)
        #expect(compressed.prefix(2) == [0x78, 0x9C])  // zlib's own default-level CMF/FLG header
    }

    @Test
    func compress_whenGzipWindowBits_roundTripsThroughZlibsOwnInflate() throws {
        // Given
        let original = Array("The quick brown fox jumps over the lazy dog.".utf8)

        // When
        let compressed = try compress(windowBits: 15 + 16, chunks: [original])

        // Then
        #expect(decompress(windowBits: 15 + 16, compressed) == original)
        #expect(compressed.prefix(3) == [0x1F, 0x8B, 0x08])  // gzip magic + CM: deflate
    }

    @Test
    func compress_whenManySmallChunks_reassemblesExactlyInOrder() throws {
        // Given: forces `drain(flush:)`'s output loop to run across many `compress(_:)` calls
        // and, since the output buffer is much larger than any one input chunk here, several
        // `avail_out == 0` iterations don't apply — this instead stresses accumulation across
        // many separate `compress(_:)` calls feeding the same live stream.
        let original = (0..<5_000).map { UInt8($0 % 251) }
        let chunks = original.map { [$0] }

        // When
        let compressed = try compress(windowBits: 15, chunks: chunks)

        // Then
        #expect(decompress(windowBits: 15, compressed) == original)
    }

    @Test
    func compress_whenOutputExceedsOneChunkBuffer_drainLoopReassemblesExactly() throws {
        // Given: larger than `PortableZlibCompressorStream`'s internal 32 KiB output-draining
        // buffer, and incompressible (random-ish, via a simple LCG) so the compressed output
        // itself also exceeds one internal buffer — exercises the `avail_out == 0` repeat loop
        // inside a single `drain(flush:)` call, not just repeated calls.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        let original: [UInt8] = (0..<200_000).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        }

        // When
        let compressed = try compress(windowBits: 15, chunks: [original])

        // Then
        #expect(decompress(windowBits: 15, compressed) == original)
    }

    @Test
    func compress_whenBodyIsEmpty_producesAValidEmptyStream() throws {
        // When
        let compressed = try compress(windowBits: 15, chunks: [])

        // Then
        #expect(decompress(windowBits: 15, compressed).isEmpty)
    }

    @Test
    func compress_whenSingleEmptyChunk_producesAValidEmptyStream() throws {
        // When
        let compressed = try compress(windowBits: 15, chunks: [[]])

        // Then
        #expect(decompress(windowBits: 15, compressed).isEmpty)
    }

    // MARK: - PortableDeflateCompressorStream / PortableGzipCompressorStream

    /// Constructs the two thin wrappers directly, bypassing `DeflateAlgorithm`/`GzipAlgorithm`'s
    /// own `#if canImport(NIOCore)` selection (which, in this test build, always picks
    /// `NIOHTTPCompressorStreamBridge` instead): confirms each wraps
    /// `PortableZlibCompressorStream` with the `windowBits` its own doc comment claims.

    @Test
    func portableDeflateCompressorStream_roundTripsThroughZlibsOwnInflate() throws {
        // Given
        let original = Array("hello, deflate".utf8)
        var stream = try PortableDeflateCompressorStream()

        // When
        var compressed = try stream(compressing: original)
        compressed += try stream.finish()

        // Then
        #expect(decompress(windowBits: 15, compressed) == original)
    }

    @Test
    func portableGzipCompressorStream_roundTripsThroughZlibsOwnInflate() throws {
        // Given
        let original = Array("hello, gzip".utf8)
        var stream = try PortableGzipCompressorStream()

        // When
        var compressed = try stream(compressing: original)
        compressed += try stream.finish()

        // Then
        #expect(decompress(windowBits: 15 + 16, compressed) == original)
        #expect(compressed.prefix(3) == [0x1F, 0x8B, 0x08])
    }
}

#endif
