//
// See LICENSE for this package's licensing information.
//

/// A pluggable request-compression algorithm.
///
/// Conform to this to teach RequestDL a compression scheme it doesn't know natively, without
/// writing a new Task Modifier or Property -- install it via ``Property/compression(_:onDuplicateHeader:shouldCompressBodyData:)``,
/// the same way ``gzip``/``deflate`` already work.
///
/// Unlike ``Decompressor``, there's no OS-provided shortcut this package can defer to: neither
/// executor compresses an outgoing body on its own, so ``callAsFunction()`` genuinely runs on
/// every request that configures one, on every executor, whether it's one of the built-ins or a
/// third-party scheme.
///
/// `callAsFunction()` is called once per request, producing a fresh ``CompressorStream`` that
/// owns whatever mutable encode state the format needs (a zlib window, for instance) for exactly
/// that one request -- never shared or reused across requests, since this type itself is
/// `Sendable` and may be reused freely across many concurrent ones.
public protocol Compressor: Sendable {

    /// The `Content-Encoding` value this produces.
    var contentEncodingValue: String { get }

    /// Creates a new, independent encoder for one request.
    func callAsFunction() throws -> any CompressorStream
}

/// The stateful, per-request half of a ``Compressor``.
///
/// Fed the outgoing body as it becomes available. Returning `[]` is always valid: a codec may
/// buffer internally and emit nothing until it has enough to produce meaningful output -- exactly
/// how `deflate()` itself behaves, buffering several writes before flushing anything back out.
///
/// ``finish()`` is called exactly once, after the last chunk, and flushes whatever the encoder is
/// still holding (a gzip trailer/checksum, for instance) -- nothing calls this a second time to
/// give an encoder another chance.
public protocol CompressorStream {

    /// Encodes as much of `bytes` as currently possible, returning what's ready. May return `[]`.
    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8]

    /// Flushes whatever the encoder is still holding once the body has ended.
    mutating func finish() throws -> [UInt8]
}
