//
// See LICENSE for this package's licensing information.
//

/// A placeholder standing in for brotli decoding, performed natively by CFNetwork. Unlike
/// ``GzipAlgorithm``/``DeflateAlgorithm``, though, it only works under `.urlSession`.
///
/// `NIOHTTPCompression` has no brotli decoder at all, on either transport, so there is no manual
/// or native fallback anywhere else: a request that resolves to `.nio`/`.nioTransportServices`
/// while this is configured, and that actually receives a `Content-Encoding: br` response, fails
/// with ``NativeOnlyAlgorithmError`` at that point. The name is chosen so that reading it back at
/// the call site already says why.
///
/// The name is verbose on purpose: unlike gzip/deflate, this one only works standalone, under
/// one specific executor, so the call site should say so plainly.
public struct BrotliURLSessionOnlyAlgorithm: Decompressor {

    // MARK: - Public properties

    public var contentEncodingValue: String { "br" }

    // MARK: - Inits

    public init() {}

    // MARK: - Public methods

    public func callAsFunction() throws -> any DecompressorStream {
        throw NativeOnlyAlgorithmError(contentEncodingValue: contentEncodingValue)
    }
}

// MARK: - Decompressor extension

extension Decompressor where Self == BrotliURLSessionOnlyAlgorithm {

    /// Decodes brotli-encoded responses natively, by CFNetwork, under `.urlSession` only.
    public static var brotliURLSessionOnly: Self { .init() }
}
