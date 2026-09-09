//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct LanguageTagTests {

    @Test
    func stringLiteralInitMatchesRawValueInit() {
        // Given
        let literal: LanguageTag = "pt-BR"

        // Then
        #expect(literal == LanguageTag("pt-BR"))
    }

    @Test
    func initAcceptsAnyStringProtocol() {
        // Given
        let substring = "en-US en-GB".split(separator: " ").first!

        // Then
        #expect(LanguageTag(substring) == "en-US")
    }

    @Test
    func descriptionReturnsTheRawValue() {
        #expect(LanguageTag("pt-BR").description == "pt-BR")
    }
}
