//
// See LICENSE for this package's licensing information.
//

/// A placeholder standing in for brotli decoding, performed natively by CFNetwork. Unlike
/// ``GzipAlgorithm``/``DeflateAlgorithm``, though, it only works under `.urlSession`.
///
/// `NIOHTTPCompression` has no brotli decoder at all, on either transport, so there is no manual
/// or native fallback anywhere else: configuring this while pinning `.nio`/`.nioTransportServices`
/// is rejected before the request is sent (``ExecutorRequirementError``). Its
/// ``Decompressor/callAsFunction()`` throws ``NativeOnlyAlgorithmError`` if it's ever invoked,
/// which a session never does. The name is chosen so that reading it back at the call site
/// already says why.
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
