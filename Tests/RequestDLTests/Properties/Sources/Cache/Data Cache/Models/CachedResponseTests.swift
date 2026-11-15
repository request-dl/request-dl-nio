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

    // MARK: - isSameEntry(as:)

    private func entry(
        headers: [(String, String)],
        status: UInt = 200,
        varyRequestHeaders: [String: String]? = nil,
        date: Date = Date()
    ) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://localhost/",
                status: .init(code: status, reason: "Ok"),
                version: .init(minor: 1, major: 1),
                headers: headers.map { .init(name: $0.0, value: $0.1) },
                isKeepAlive: true
            ),
            policy: .all,
            varyRequestHeaders: varyRequestHeaders,
            date: date
        )
    }

    /// What two revalidations of one entry leave behind: the same response, each with its own date
    /// and the freshness headers its own 304 carried, which rewriting puts at the end.
    @Test
    func isSameEntry_whenOnlyTheDateAndTheFreshnessHeadersDiffer_isTrue() {
        // Given
        let stored = entry(
            headers: [("ETag", "\"v1\""), ("Cache-Control", "max-age=5"), ("Age", "3"), ("Expires", "x")],
            date: Date(timeIntervalSince1970: 1)
        )

        let renewed = entry(
            headers: [("etag", "\"v1\""), ("Cache-Control", "max-age=7200")],
            date: Date(timeIntervalSince1970: 2)
        )

        // Then
        #expect(renewed.isSameEntry(as: stored))
        #expect(stored.isSameEntry(as: renewed))
    }

    @Test
    func isSameEntry_whenAValidatorStatusOrCredentialDiffers_isFalse() {
        // Given
        let stored = entry(headers: [("ETag", "\"v1\"")], varyRequestHeaders: ["authorization": "user1"])

        // Then
        #expect(
            !entry(headers: [("ETag", "\"v2\"")], varyRequestHeaders: ["authorization": "user1"]).isSameEntry(
                as: stored
            )
        )
        #expect(!entry(headers: [], varyRequestHeaders: ["authorization": "user1"]).isSameEntry(as: stored))
        #expect(
            !entry(headers: [("ETag", "\"v1\"")], status: 404, varyRequestHeaders: ["authorization": "user1"])
                .isSameEntry(as: stored)
        )
        #expect(
            !entry(headers: [("ETag", "\"v1\"")], varyRequestHeaders: ["authorization": "user2"]).isSameEntry(
                as: stored
            )
        )
        #expect(!entry(headers: [("ETag", "\"v1\"")]).isSameEntry(as: stored))
    }
}
