//
// See LICENSE for this package's licensing information.
//

// Only actually chosen with the `NIOTransport` trait disabled. `GzipAlgorithm.callAsFunction()`
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

/// Portable ``CompressorStream`` behind ``GzipAlgorithm`` when NIO isn't available, producing the
/// same wire format (`Content-Encoding: gzip`, i.e. an RFC 1952 gzip stream) that
/// ``NIOHTTPCompressorStreamBridge`` produces through `NIOHTTPRequestCompressor`, using zlib's
/// own incremental `deflate()` API (via ``PortableZlibCompressorStream``) instead. It's the gzip
/// counterpart of ``PortableDeflateCompressorStream``.
///
/// `windowBits + 16` (rather than `PortableDeflateCompressorStream`'s plain `windowBits`) is
/// zlib's own documented switch for producing an RFC 1952 gzip container, with its magic number,
/// flags, mtime and CRC-32 trailer, instead of an RFC 1950 zlib one, wrapping the same raw
/// deflate bytes either way.
struct PortableGzipCompressorStream: CompressorStream {

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
        stream = try PortableZlibCompressorStream(windowBits: 15 + 16)
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
