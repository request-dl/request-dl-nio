//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct RequestBodyTests {

    // `RequestBody`'s `AsyncSequence` conformance (`makeAsyncIterator()`/`AsyncIterator.next()`)
    // is public API for consumers who want the raw `Data` chunks directly. `build(eventLoop:)`
    // goes through `Internals.StreamWriterSequence` for the `.nio` executor instead, but
    // `buildURLRequest()`/`CURLTaskDescriptor` both drive this conformance directly too.
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
        var collected = Data()

        for try await chunk in body {
            collected += chunk
        }

        // Then
        #expect(collected == Data(verbatim.utf8))
    }
}
