//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Testing

@testable import RequestDLInternals

struct InternalsDecompressionTests {

    /// `isNativelyDecodedByURLSession`/`isNativelyDecodedByNIO: true` here stand in for what
    /// `InternalsDecompressionAlgorithmAdapter` (in `RequestDL`) actually answers for the real
    /// `GzipAlgorithm` -- a structural type check, not a `contentEncodingValue` comparison. See
    /// `MockCustomAlgorithmNamedGzip` below for why that distinction is the whole point.
    private struct MockGzipAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "gzip" }
        var isNativelyDecodedByURLSession: Bool { true }
        var isNativelyDecodedByNIO: Bool { true }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    private struct MockDeflateAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "deflate" }
        var isNativelyDecodedByURLSession: Bool { true }
        var isNativelyDecodedByNIO: Bool { true }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    private struct MockCustomAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "zstd" }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    /// A genuinely custom algorithm that happens to share `contentEncodingValue` with the
    /// built-in `GzipAlgorithm` -- `isNativelyDecodedByURLSession`/`isNativelyDecodedByNIO` both
    /// default to `false` (neither is overridden here), matching what a real third-party
    /// `Decompressor` gets. This is exactly the case the type-based checks exist for: without
    /// them, this would be indistinguishable from `MockGzipAlgorithm` above and would get
    /// silently bypassed -- by CFNetwork under `.urlSession`, by `NIOHTTPResponseDecompressor`
    /// under `.nio`/`.nioTransportServices` -- instead of actually running.
    private struct MockCustomAlgorithmNamedGzip: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "gzip" }
        func callAsFunction() throws -> any Internals.DecompressorStream {
            fatalError("not exercised")
        }
    }

    @Test
    func decompression_whenDisabled() {
        // Given
        let decompression = Internals.Decompression.disabled

        // When
        let sut = decompression.build()

        // Then
        #expect(
            String(describing: sut)
                == String(
                    describing: HTTPClient.Decompression.disabled
                )
        )
        #expect(decompression.requiresManualURLSessionHandling)
        #expect(decompression.algorithms.isEmpty)
    }

    @Test
    func decompression_whenEnabledWithNativeAlgorithms_buildsEnabled() {
        // Given
        let decompression = Internals.Decompression.enabled(
            algorithms: [MockGzipAlgorithm(), MockDeflateAlgorithm()],
            limit: .ratio(1_024)
        )

        // When
        let sut = decompression.build()

        // Then -- gzip/deflate are always delegated to `async-http-client`'s own native handler,
        // regardless of what else is configured alongside them.
        #expect(
            String(describing: sut)
                == String(
                    describing: HTTPClient.Decompression.enabled(limit: .ratio(1_024))
                )
        )
        #expect(!decompression.requiresManualURLSessionHandling)
    }

    @Test
    func decompression_whenEnabledWithOnlyCustomAlgorithm_buildsDisabled() {
        // Given -- nothing `NIOHTTPResponseDecompressor` recognizes, so the native NIO handler
        // stays off and manual dispatch owns the whole response.
        let decompression = Internals.Decompression.enabled(
            algorithms: [MockCustomAlgorithm()],
            limit: .none
        )

        // When
        let sut = decompression.build()

        // Then
        #expect(String(describing: sut) == String(describing: HTTPClient.Decompression.disabled))
        #expect(decompression.requiresManualURLSessionHandling)
    }

    @Test
    func decompression_whenCustomAlgorithmSharesGzipContentEncoding_stillRequiresManualURLSessionHandling() {
        // Given -- a genuinely custom algorithm whose `contentEncodingValue` happens to be
        // "gzip", same as the built-in placeholder. `isNativelyDecodedByURLSession` is a
        // structural check against the built-in types, not a `contentEncodingValue` comparison,
        // so this must NOT be treated the same as `MockGzipAlgorithm` -- otherwise `.urlSession`
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
    func decompression_whenCustomAlgorithmSharesGzipContentEncoding_buildsDisabledUnderNIO() {
        // Given -- same collision as the `.urlSession` test above, but checked against the NIO
        // side: `NIOHTTPResponseDecompressor` is a single switch triggered purely by the
        // response's `Content-Encoding` header, so leaving it on here would decode the response
        // before this custom algorithm's manual dispatch ever got a chance to run.
        let decompression = Internals.Decompression.enabled(
            algorithms: [MockCustomAlgorithmNamedGzip()],
            limit: .none
        )

        // Then
        #expect(
            String(describing: decompression.build()) == String(describing: HTTPClient.Decompression.disabled)
        )
    }

    @Test
    func decompression_whenEnabledMixingNativeAndCustom_requiresManualURLSessionHandling() {
        // Given
        let decompression = Internals.Decompression.enabled(
            algorithms: [MockGzipAlgorithm(), MockCustomAlgorithm()],
            limit: .none
        )

        // Then -- `.urlSession` can't leave CFNetwork decoding gzip transparently while also
        // taking over `Accept-Encoding` for the custom algorithm -- the moment anything
        // non-native is in the list, this package decodes everything in it itself.
        #expect(decompression.requiresManualURLSessionHandling)

        // NIO has no such constraint: its own native handler still only ever sees gzip, and
        // manual dispatch downstream picks up whatever it doesn't touch.
        #expect(
            String(describing: decompression.build())
                == String(describing: HTTPClient.Decompression.enabled(limit: .none))
        )
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
        // Given -- equality compares the set of `Content-Encoding` values and the limit, not
        // algorithm identity, so two configurations that behave identically are equal.
        let lhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)
        let rhs = Internals.Decompression.enabled(algorithms: [MockGzipAlgorithm()], limit: .none)

        // Then
        #expect(lhs == rhs)
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
