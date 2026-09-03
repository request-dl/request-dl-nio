//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct AcceptEncodingHeaderTests {

    @Test
    func singleCodingGetsFullWeight() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                AcceptEncodingHeader(.gzip)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Encoding"] == ["gzip;q=1.0"])
    }

    @Test
    func multipleCodingsDescendInWeightByPosition() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                AcceptEncodingHeader(.gzip, .deflate, .identity)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.headers["Accept-Encoding"] == [
                "gzip;q=1.0, deflate;q=0.9, identity;q=0.8"
            ]
        )
    }

    @Test
    func weightNeverDropsBelowTheFloor() async throws {
        // Given
        let codings = (0...10).map { ContentCoding("c\($0)") }

        // When
        let resolved = try await resolve(
            TestProperty {
                AcceptEncodingHeader(
                    codings[0],
                    codings[1],
                    codings[2],
                    codings[3],
                    codings[4],
                    codings[5],
                    codings[6],
                    codings[7],
                    codings[8],
                    codings[9],
                    codings[10]
                )
            }
        )

        // Then
        // Index 9 already floors at 0.1 (1 - 9 * 0.1); index 10 would go negative without the
        // floor, so both land on the same weight.
        let value = try #require(resolved.requestConfiguration.headers["Accept-Encoding"]?.first)
        #expect(value.hasSuffix("c9;q=0.1, c10;q=0.1"))
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = AcceptEncodingHeader(.gzip)

        // Then
        try await assertNever(property.body)
    }
}
