//
// See LICENSE for this package's licensing information.
//

// Every test here calls `decompression.build()`, which returns AsyncHTTPClient's `HTTPClient
// .Decompression` and only exists under `canImport(NIOCore)`. See the main declaration's own
// doc comment, in `InternalsDecompressionTests.swift`.
#if canImport(NIOCore)

import AsyncHTTPClient
import Testing

@testable import RequestDLInternals

extension InternalsDecompressionTests {

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

        // Then: gzip/deflate are always delegated to `async-http-client`'s own native handler,
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
        // Given: nothing `NIOHTTPResponseDecompressor` recognizes, so the native NIO handler
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
    func decompression_whenCustomAlgorithmSharesGzipContentEncoding_buildsDisabledUnderNIO() {
        // Given: same collision as the `.urlSession` test in the main file, but checked against
        // the NIO side: `NIOHTTPResponseDecompressor` is a single switch triggered purely by the
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

        // Then: `.urlSession` can't leave CFNetwork decoding gzip transparently while also
        // taking over `Accept-Encoding` for the custom algorithm. The moment anything
        // non-native is in the list, this package decodes everything in it itself.
        #expect(decompression.requiresManualURLSessionHandling)

        // NIO has no such constraint: its own native handler still only ever sees gzip, and
        // manual dispatch downstream picks up whatever it doesn't touch.
        #expect(
            String(describing: decompression.build())
                == String(describing: HTTPClient.Decompression.enabled(limit: .none))
        )
    }
}

#endif
