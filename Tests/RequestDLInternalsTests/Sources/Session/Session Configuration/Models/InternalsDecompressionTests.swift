//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

/// Only the tests that never call `decompression.build()` (returns AsyncHTTPClient's `HTTPClient
/// .Decompression`, only exists under `canImport(NIOCore)`) stay here. The rest live in
/// `InternalsDecompressionTests+NIO.swift`.
struct InternalsDecompressionTests {

    /// `isNativelyDecodedByURLSession`/`isNativelyDecodedByNIO: true` here stand in for what
    /// `InternalsDecompressionAlgorithmAdapter` (in `RequestDL`) actually answers for the real
    /// `GzipAlgorithm`: a structural type check, not a `contentEncodingValue` comparison. See
    /// `MockCustomAlgorithmNamedGzip` below for why that distinction is the whole point.
    ///
    /// Not `private`: shared with the `.build()`-dependent tests split out into
    /// `InternalsDecompressionTests+NIO.swift`.
    struct MockGzipAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "gzip" }
        var isNativelyDecodedByURLSession: Bool { true }
        var isNativelyDecodedByNIO: Bool { true }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    struct MockDeflateAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "deflate" }
        var isNativelyDecodedByURLSession: Bool { true }
        var isNativelyDecodedByNIO: Bool { true }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    struct MockCustomAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "zstd" }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    /// A genuinely custom algorithm that happens to share `contentEncodingValue` with the
    /// built-in `GzipAlgorithm`: `isNativelyDecodedByURLSession`/`isNativelyDecodedByNIO` both
    /// default to `false` (neither is overridden here), matching what a real third-party
    /// `Decompressor` gets.
    ///
    /// This is exactly the case the type-based checks exist for: without them, this would be
    /// indistinguishable from `MockGzipAlgorithm` above and would get silently bypassed instead
    /// of actually running (by CFNetwork under `.urlSession`, by `NIOHTTPResponseDecompressor`
    /// under `.nio`/`.nioTransportServices`).
    struct MockCustomAlgorithmNamedGzip: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "gzip" }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    @Test
    func decompression_whenCustomAlgorithmSharesGzipContentEncoding_stillRequiresManualURLSessionHandling() {
        // Given: a genuinely custom algorithm whose `contentEncodingValue` happens to be
        // "gzip", same as the built-in placeholder. `isNativelyDecodedByURLSession` is a
        // structural check against the built-in types, not a `contentEncodingValue` comparison,
        // so this must NOT be treated the same as `MockGzipAlgorithm`; otherwise `.urlSession`
        // would let CFNetwork decode the response transparently and this algorithm would never
        // actually run.
        let decompression = Internals.Decompression.enabled(
            algorithms: [MockCustomAlgorithmNamedGzip()],
            limit: .none
        )

        // Then
        #expect(decompression.requiresManualURLSessionHandling)
    }

    @Test
    func decompression_whenEquals() {
        // Given
        let lhs = Internals.Decompression.disabled
        let rhs = Internals.Decompression.disabled

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func decompression_whenEnabledWithSameContentEncodingValues_equals() {
        // Given: equality compares the set of `Content-Encoding` values and the limit, not
        // algorithm identity, so two configurations that behave identically are equal.
        let lhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)
        let rhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)

        // Then
        #expect(lhs == rhs)
    }

    /// Regression coverage for a pooled-client cache collision: equality used to compare only the
    /// set of `Content-Encoding` values, which is exactly the check
    /// `Internals.DecompressionAlgorithm` documents as *not* being what decides behavior. A
    /// custom algorithm declaring `"gzip"` needs `build()` to leave
    /// `NIOHTTPResponseDecompressor` off so manual dispatch actually runs it; the built-in
    /// placeholder needs it on. `Internals.ClientManager` keys pooled clients on
    /// `Internals.Session.Configuration.==`, and `build()`'s answer is baked into the
    /// `HTTPClient`, so the two must not compare equal.
    @Test
    func decompression_whenCustomAlgorithmSharesGzipContentEncoding_notEqualToNativeGzip() {
        // Given
        let lhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)
        let rhs = Internals.Decompression.enabled(algorithms: [MockCustomAlgorithmNamedGzip()], limit: .none)

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func decompression_whenEnabledWithDifferentLimit_notEquals() {
        // Given
        let lhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)
        let rhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .ratio(10))

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func decompression_whenNotEquals() {
        // Given
        let lhs = Internals.Decompression.disabled
        let rhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)

        // Then
        #expect(lhs != rhs)
    }
}
