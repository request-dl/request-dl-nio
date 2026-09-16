//
// See LICENSE for this package's licensing information.
//

// `Internals.NIOHTTPCompressorStream` (what this bridges to) is itself unconditionally NIO-only
// — see that type's own doc comment — so there's nothing this bridge could do without NIO
// either. `GzipAlgorithm`/`DeflateAlgorithm` fall back to ``CompressionUnavailableError`` when
// this type doesn't exist at all.
#if canImport(NIOCore)

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Bridges `Internals.NIOHTTPCompressorStream` (`Data`-based, `NIOCore.ByteBuffer` only as an
/// implementation detail) onto the public, `[UInt8]`-based ``CompressorStream``. It backs
/// ``GzipAlgorithm``/``DeflateAlgorithm``, the only two built-in ``Compressor``s that do real
/// work rather than throw ``NativeOnlyAlgorithmError``, since there is no OS-provided
/// outgoing-compression shortcut either of them could defer to instead.
struct NIOHTTPCompressorStreamBridge: CompressorStream {

    // MARK: - Private properties

    private var stream: Internals.NIOHTTPCompressorStream

    // MARK: - Inits

    init(algorithm: Internals.Compression.Algorithm) throws {
        stream = try Internals.NIOHTTPCompressorStream(algorithm: algorithm)
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
        Array(try stream(compressing: Data(bytes)))
    }

    mutating func finish() throws -> [UInt8] {
        Array(try stream.finish())
    }
}

#endif
