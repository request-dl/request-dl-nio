//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct StringMethodsTests {

    @Test
    func tokenAllowedCharactersPassThroughUnchanged() {
        let allowed = "AZaz09!#$%&'*+-.^_`|~"
        #expect(allowed.sanitizedAsRFC9110Token == allowed)
    }

    @Test
    func spacesAndOtherDisallowedCharactersAreReplacedWithAHyphen() {
        #expect("My App (Beta)".sanitizedAsRFC9110Token == "My-App--Beta-")
    }

    @Test
    func nonASCIICharactersAreReplacedWithAHyphen() {
        #expect("café".sanitizedAsRFC9110Token == "caf-")
    }

    @Test
    func emptyInputFallsBackToAHyphen() {
        #expect("".sanitizedAsRFC9110Token == "-")
    }

    @Test
    func fullyDisallowedInputReplacesEachCharacterWithAHyphen() {
        #expect("   ".sanitizedAsRFC9110Token == "---")
    }
}
