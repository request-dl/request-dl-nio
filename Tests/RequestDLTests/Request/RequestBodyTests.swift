//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals
import Testing

@testable import RequestDL

struct RequestBodyTests {

    // `RequestBody`'s `AsyncSequence` conformance (`makeAsyncIterator()`/`AsyncIterator.next()`)
    // is public API for consumers who want the raw chunks directly, but nothing in `Sources/`
    // drives it — `build(eventLoop:)` goes through `Internals.StreamWriterSequence` instead.
    // `Internals.BodySequence.AsyncIterator` is self-contained (no writer coupling), so it can be
    // iterated directly without standing in for `HTTPClient.Body.StreamWriter`.
    @Test
    func requestBody_asAsyncSequence_yieldsAllBytes() async throws {
        // Given
        let verbatim = "Hello, RequestBody!"

        let resolved = try await resolve(
            TestProperty {
                Payload(verbatim: verbatim)
            }
        )

        let body = try #require(resolved.requestConfiguration.body)

        // When
        var collected = [UInt8]()

        for await chunk in body {
            collected += Array(chunk.readableBytesView)
        }

        // Then
        #expect(collected == Array(verbatim.utf8))
    }
}
