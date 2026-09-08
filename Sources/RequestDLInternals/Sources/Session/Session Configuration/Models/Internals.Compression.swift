//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOHTTPCompression

extension Internals {

    /// Namespace only -- compression no longer lives on `Internals.Session.Configuration` (it's
    /// per-request/environment-driven now, via `RequestConfiguration`, not session-pooled), so
    /// there's no `.disabled`/`.enabled` state to carry here anymore. `Algorithm` and
    /// `DuplicateHeaderBehavior` stay nested under this name purely to avoid churning every
    /// existing reference to `Internals.Compression.Algorithm`/`.DuplicateHeaderBehavior`.
    package enum Compression: Sendable {}
}

extension Internals.Compression {

    /// The two algorithms `NIOHTTPRequestCompressor` (and therefore
    /// `Internals.NIOHTTPCompressorStream`) actually knows how to produce.
    package enum Algorithm: Sendable, Hashable {

        case gzip
        case deflate

        // MARK: - Internal methods

        package func build() -> NIOCompression.Algorithm {
            switch self {
            case .gzip:
                return .gzip
            case .deflate:
                return .deflate
            }
        }
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

    /// Internals-layer counterpart to `RequestDL.Compressor`. Shared by both transports -- though
    /// unlike decompression, compression always runs through this package's own code on every
    /// executor (there is no native, OS-provided outgoing-compression equivalent to CFNetwork's
    /// transparent response decoding to defer to), so a compressor configured through the public
    /// protocol behaves identically everywhere for that simpler reason.
    package protocol CompressionAlgorithm: Sendable {
        var contentEncodingValue: String { get }
        func callAsFunction() throws -> any Internals.CompressorStream
    }

    /// Internals-layer counterpart to `RequestDL.CompressorStream`, operating on `ByteBuffer`
    /// instead of `[UInt8]` -- the boundary conversion lives in the adapter that wraps a public
    /// `Compressor`/`CompressorStream` into these.
    package protocol CompressorStream {
        mutating func callAsFunction(compressing bytes: ByteBuffer) throws -> ByteBuffer
        mutating func finish() throws -> ByteBuffer
    }
}
