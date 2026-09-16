//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOHTTPCompression
#endif

extension Internals {

    /// Namespace only: compression is per-request/environment-driven, carried on
    /// `RequestConfiguration` rather than pooled on the session, so there's no `.disabled`/
    /// `.enabled` state to carry here. `Algorithm` and `DuplicateHeaderBehavior` stay nested
    /// under this name to group them with the rest of the compression-related types below.
    package enum Compression: Sendable {}
}

extension Internals.Compression {

    /// The two algorithms `NIOHTTPRequestCompressor` (and therefore
    /// `Internals.NIOHTTPCompressorStream`) actually knows how to produce.
    package enum Algorithm: Sendable, Hashable {

        case gzip
        case deflate

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> NIOCompression.Algorithm {
            switch self {
            case .gzip:
                return .gzip
            case .deflate:
                return .deflate
            }
        }
        #endif
    }

    /// What to do when the request already carries a `Content-Encoding` header before
    /// compression would set its own. Mirrors the public `CompressionDuplicateHeaderBehavior`,
    /// which is the type this one is built from.
    package enum DuplicateHeaderBehavior: Sendable, Hashable {

        case error
        case replace
        case skip
    }
}

extension Internals {

    /// Internals-layer counterpart to `RequestDL.Compressor`. Shared by both transports, though
    /// unlike decompression, compression always runs through this package's own code on every
    /// executor (there is no native, OS-provided outgoing-compression equivalent to CFNetwork's
    /// transparent response decoding to defer to), so a compressor configured through the public
    /// protocol behaves identically everywhere for that simpler reason.
    package protocol CompressionAlgorithm: Sendable {
        var contentEncodingValue: String { get }
        func callAsFunction() throws -> any Internals.CompressorStream
    }

    /// Internals-layer counterpart to `RequestDL.CompressorStream`, operating on
    /// `Internals.Bytes` instead of `[UInt8]`: the boundary conversion lives in the adapter that
    /// wraps a public `Compressor`/`CompressorStream` into these. The one conformer that does
    /// real work (`Internals.NIOHTTPCompressorStream`) runs on `NIOCore.ByteBuffer` internally
    /// and hands back a `ByteBuffer`-backed `Internals.Bytes`, so a chunk that arrived already
    /// `ByteBuffer`-backed crosses this boundary without a copy.
    package protocol CompressorStream {
        mutating func callAsFunction(compressing bytes: Internals.Bytes) throws -> Internals.Bytes
        mutating func finish() throws -> Internals.Bytes
    }
}
