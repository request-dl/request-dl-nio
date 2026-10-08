//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.Date
#endif

struct CachedResponseTests {

    private func response() -> Internals.ResponseHead {
        .init(
            url: "https://localhost/",
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 1),
            headers: [.init(name: "Vary", value: "Accept-Language")],
            isKeepAlive: true
        )
    }

    @Test
    func cachedResponse_whenEncodedAndDecoded_keepsTheRecordedVaryHeaders() throws {
        // Given
        let cachedResponse = CachedResponse(
            response: response(),
            policy: .all,
            varyRequestHeaders: ["accept-language": "pt-BR"]
        )

        // When
        let decoded = try JSONDecoder().decode(
            CachedResponse.self,
            from: JSONEncoder().encode(cachedResponse)
        )

        // Then
        #expect(decoded.varyRequestHeaders == ["accept-language": "pt-BR"])
    }

    /// Entries already on disk were written before `varyRequestHeaders` existed, and must still
    /// decode.
    @Test
    func cachedResponse_whenDecodedFromAnEntryWrittenBeforeVaryWasRecorded_hasNone() throws {
        // Given: the shape that was written before the field existed.
        struct Written: Encodable {
            let response: Internals.ResponseHead
            let policy: DataCache.Policy.Set
            let date: Date
        }

        let data = try JSONEncoder().encode(
            Written(response: response(), policy: .all, date: Date())
        )

        // When
        let decoded = try JSONDecoder().decode(CachedResponse.self, from: data)

        // Then
        #expect(decoded.varyRequestHeaders == nil)
    }
}
