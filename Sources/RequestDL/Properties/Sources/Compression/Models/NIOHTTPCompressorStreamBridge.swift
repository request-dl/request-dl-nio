//
// See LICENSE for this package's licensing information.
//

// `Internals.NIOHTTPCompressorStream` (what this bridges to) is itself unconditionally NIO-only
// (see that type's own doc comment), so there's nothing this bridge could do without NIO
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

    // MARK: - Internal properties

    /// The `Internals.Bytes`-native stream this bridges to the public `[UInt8]`-based
    /// `CompressorStream`. `InternalsCompressionAlgorithmAdapter` reaches for this directly
    /// instead of going through `callAsFunction(compressing:)` below, so driving gzip/deflate
    /// from inside the package skips the round trip through `[UInt8]`/`Data` entirely. That
    /// conversion only exists for a genuinely custom, `[UInt8]`-based `Compressor`.
    var nativeStream: Internals.NIOHTTPCompressorStream { stream }

    // MARK: - Inits

    init(algorithm: Internals.Compression.Algorithm) throws {
        stream = try Internals.NIOHTTPCompressorStream(algorithm: algorithm)
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
        var result = try stream(compressing: Internals.Bytes(Data(bytes)))
        return Array(result.asData())
    }

    mutating func finish() throws -> [UInt8] {
        var result = try stream.finish()
        return Array(result.asData())
    }
}

#endif
