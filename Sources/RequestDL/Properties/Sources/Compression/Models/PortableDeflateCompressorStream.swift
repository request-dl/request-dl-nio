//
// See LICENSE for this package's licensing information.
//

// Only actually chosen once the future URLSession-only trait exists: `DeflateAlgorithm.callAsFunction()`
// only reaches the `#elseif canImport(zlib)` branch that constructs this when `canImport(NIOCore)`
// is false. The type itself compiles (and is covered by `InternalsPortableZlibCompressorStreamTests`)
// in every build, gated only on `canImport(zlib)`. See `PortableZlibCompressorStream`'s own doc
// comment for why that's a wider gate than "chosen at runtime" needs.
#if canImport(zlib)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Portable ``CompressorStream`` behind ``DeflateAlgorithm`` when NIO isn't available, producing
/// the same wire format (`Content-Encoding: deflate`, i.e. an RFC 1950 zlib-wrapped deflate
/// stream) that ``NIOHTTPCompressorStreamBridge`` produces through `NIOHTTPRequestCompressor`,
/// using zlib's own incremental `deflate()` API (via ``PortableZlibCompressorStream``) instead.
struct PortableDeflateCompressorStream: CompressorStream {

    // MARK: - Private properties

    private let stream: PortableZlibCompressorStream

    // MARK: - Internal properties

    /// The `Internals.Bytes`-native stream this bridges to the public, `[UInt8]`-based
    /// `CompressorStream`. See ``PortableZlibCompressorNativeStream``'s own doc comment.
    var nativeStream: PortableZlibCompressorNativeStream {
        .init(stream: stream)
    }

    // MARK: - Inits

    init() throws {
        stream = try PortableZlibCompressorStream(windowBits: 15)
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
        Array(try stream.compress(Data(bytes)))
    }

    mutating func finish() throws -> [UInt8] {
        Array(try stream.finish())
    }
}

#endif
