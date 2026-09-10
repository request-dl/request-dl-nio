//
// See LICENSE for this package's licensing information.
//

import NIOCore

extension Internals {

    /// Internals-layer counterpart to `RequestDL.Decompressor`. Shared by both transports so a
    /// decompressor configured through the public protocol behaves identically under either.
    /// See `Internals.Decompression` for how each executor actually consumes this.
    package protocol DecompressionAlgorithm: Sendable {
        var contentEncodingValue: String { get }

        /// Mirrors `RequestDL.Decompressor.requiresURLSession`. See
        /// `Internals.Session.Configuration.nonURLSessionExecutorIncompatibilityReasons()` for
        /// what configuring one of these actually does to executor resolution.
        var requiresURLSession: Bool { get }

        /// Whether CFNetwork decodes this *specific algorithm* transparently under `.urlSession`,
        /// with no way to opt out short of taking over `Accept-Encoding` entirely. See
        /// `Internals.Decompression.requiresManualURLSessionHandling`.
        ///
        /// Deliberately a per-conformer answer, not a check against `contentEncodingValue`.
        /// `InternalsDecompressionAlgorithmAdapter` (in `RequestDL`) overrides this to `true` only
        /// for the exact built-in types (`GzipAlgorithm`, `DeflateAlgorithm`,
        /// `BrotliURLSessionOnlyAlgorithm`) that are themselves nothing but placeholders standing
        /// in for CFNetwork's own decoding.
        ///
        /// A genuinely custom `Decompressor` that happens to declare
        /// `contentEncodingValue == "gzip"` is not one of those: its whole point is to run its
        /// own logic, so this must default to `false` for it, forcing manual dispatch (and thus
        /// actually invoking it) rather than silently deferring to CFNetwork the same way the
        /// built-in placeholder would.
        var isNativelyDecodedByURLSession: Bool { get }

        /// Whether `async-http-client`'s own `NIOHTTPResponseDecompressor` decodes this *specific
        /// algorithm* transparently under `.nio`/`.nioTransportServices`. See
        /// `Internals.Decompression.build()`.
        ///
        /// Same reasoning as `isNativelyDecodedByURLSession`, and the same structural, per-type
        /// check in `InternalsDecompressionAlgorithmAdapter` (`GzipAlgorithm`/`DeflateAlgorithm`
        /// only: `NIOHTTPCompression` has no brotli decoder at all, so
        /// `BrotliURLSessionOnlyAlgorithm` is never natively decoded here).
        ///
        /// A custom `Decompressor` declaring `contentEncodingValue == "gzip"` must default to
        /// `false`: `async-http-client`'s decompressor is a single switch triggered purely by the
        /// response's own `Content-Encoding` header, with no notion of which algorithm instance
        /// was configured, so leaving it on for a wire value a custom algorithm claims would
        /// decode the response out from under it before manual dispatch ever got a chance to run.
        var isNativelyDecodedByNIO: Bool { get }

        func callAsFunction() throws -> any Internals.DecompressorStream
    }

    /// Internals-layer counterpart to `RequestDL.DecompressorStream`, operating on `ByteBuffer`
    /// instead of `[UInt8]`; the boundary conversion lives in the adapter that wraps a public
    /// `Decompressor`/`DecompressorStream` into these.
    package protocol DecompressorStream {
        mutating func callAsFunction(decompressing bytes: ByteBuffer) throws -> ByteBuffer
        mutating func finish() throws -> ByteBuffer
    }
}

extension Internals.DecompressionAlgorithm {

    package var requiresURLSession: Bool { false }

    package var isNativelyDecodedByURLSession: Bool { false }

    package var isNativelyDecodedByNIO: Bool { false }
}
