//
// See LICENSE for this package's licensing information.
//

/// A pluggable response-decompression algorithm.
///
/// Conform to this to teach RequestDL a `Content-Encoding` it doesn't know natively, without
/// writing a new Task Modifier or Property; install it via
/// ``Session/decompressionAlgorithms(_:limit:)``, the same way ``gzip``/``deflate`` already work.
///
/// `callAsFunction()` is called once per response whose `Content-Encoding` matches
/// ``contentEncodingValue``, producing a fresh ``DecompressorStream`` that owns whatever mutable
/// decode state the format needs (a zlib window, for instance) for exactly that one response.
/// It's never shared or reused across requests, since this type itself is `Sendable` and may be
/// reused freely across many concurrent ones.
public protocol Decompressor: Sendable {

    /// The `Content-Encoding` value this decompresses, compared case-insensitively against the
    /// response header.
    var contentEncodingValue: String { get }

    /// Creates a new, independent decoder for one response.
    func callAsFunction() throws -> any DecompressorStream
}

/// The stateful, per-response half of a ``Decompressor``.
///
/// Fed the response body as it arrives, in whatever chunk sizes the transport happens to
/// deliver. There is no guarantee a chunk lines up with any boundary the encoder produced, so
/// an implementation that needs to track state across calls (most real codecs do) must do so
/// internally.
///
/// Returning `[]` is always valid: a codec may buffer internally and emit nothing
/// until it has enough to decode, including a codec that can only ever decode once it has seen
/// the entire body. That one just returns `[]` from every ``callAsFunction(decompressing:)``
/// call and does all its work in ``finish()``. It won't benefit from incremental delivery, but it
/// remains a correct, conforming implementation.
///
/// ``finish()`` is called exactly once, after the last chunk, and flushes whatever the decoder
/// is still holding. It's also where a truncated or corrupt stream should be caught and
/// thrown, since nothing calls this a second time to give a decoder another chance.
public protocol DecompressorStream {

    /// Decodes as much of `bytes` as currently possible, returning what's ready. May return `[]`.
    mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8]

    /// Flushes whatever the decoder is still holding once the body has ended.
    mutating func finish() throws -> [UInt8]
}
