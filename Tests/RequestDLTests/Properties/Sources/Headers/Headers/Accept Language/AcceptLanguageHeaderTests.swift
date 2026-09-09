//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(Darwin)
import struct Foundation.Locale
#endif

struct AcceptLanguageHeaderTests {

    @Test
    func singleLanguageGetsFullWeight() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                AcceptLanguageHeader("pt-BR")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Language"] == ["pt-BR;q=1.0"])
    }

    @Test
    func multipleLanguagesDescendInWeightByPosition() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                AcceptLanguageHeader("pt-BR", "en-US", "es")
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.headers["Accept-Language"] == [
                "pt-BR;q=1.0, en-US;q=0.9, es;q=0.8"
            ]
        )
    }

    @Test
    func weightNeverDropsBelowTheFloor() async throws {
        // Given
        let tags = (0...10).map { LanguageTag("l\($0)") }

        // When
        let resolved = try await resolve(
            TestProperty {
                AcceptLanguageHeader(
                    tags[0],
                    tags[1],
                    tags[2],
                    tags[3],
                    tags[4],
                    tags[5],
                    tags[6],
                    tags[7],
                    tags[8],
                    tags[9],
                    tags[10]
                )
            }
        )

        // Then
        // Index 9 already floors at 0.1 (1 - 9 * 0.1); index 10 would go negative without the
        // floor, so both land on the same weight.
        let value = try #require(resolved.requestConfiguration.headers["Accept-Language"]?.first)
        #expect(value.hasSuffix("l9;q=0.1, l10;q=0.1"))
    }

    #if canImport(Darwin)
    @Test
    func defaultValueUsesTheSystemsPreferredLanguages() async throws {
        // Given
        // Independently reconstructs the expected value from the same public inputs
        // (`Locale.preferredLanguages`) and the documented weighting rule, rather than reusing
        // any private implementation detail of `AcceptLanguageHeader`.
        let expectedValue = Locale.preferredLanguages.prefix(6)
            .enumerated()
            .map { index, tag in
                let quality = max(0.1, 1 - Double(index) * 0.1)
                return "\(tag);q=\(quality.fixed(fractionDigits: 1))"
            }
            .joined(separator: ", ")

        // When
        let resolved = try await resolve(
            TestProperty {
                AcceptLanguageHeader()
            }
        )

        // Then
        #expect(resolved.requestConfiguration.headers["Accept-Language"] == [expectedValue])
    }
    #endif

    @Test
    func neverBody() async throws {
        // Given
        let property = AcceptLanguageHeader("en")

        // Then
        try await assertNever(property.body)
    }
}
