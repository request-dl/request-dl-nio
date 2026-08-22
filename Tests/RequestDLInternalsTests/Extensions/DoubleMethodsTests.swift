//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct DoubleMethodsTests {

    @Test
    func nonFiniteValuesFallBackToTheirDefaultDescription() {
        #expect(Double.infinity.fixed(fractionDigits: 2) == "\(Double.infinity)")
        #expect(Double.nan.fixed(fractionDigits: 2) == "\(Double.nan)")
    }

    @Test
    func zeroOrFewerFractionDigitsRoundsToAnInteger() {
        #expect((3.7).fixed(fractionDigits: 0) == "4")
        #expect((3.2).fixed(fractionDigits: -1) == "3")
    }

    @Test
    func fractionShorterThanRequestedDigitsIsLeftPadded() {
        // 1.05 scaled by 1000 rounds to a two-digit fraction ("50"), which needs a leading
        // zero to reach the requested 3 fraction digits.
        #expect((1.05).fixed(fractionDigits: 3) == "1.050")
    }

    @Test
    func negativeValueThatRoundsToZeroWholeKeepsItsSign() {
        // -0.001 scaled by 100 and rounded lands on -0.0: the sign would otherwise be lost
        // since `whole` itself prints as "0".
        #expect((-0.001).fixed(fractionDigits: 2) == "-0.00")
    }

    @Test
    func typicalPositiveValueFormatsWithTheRequestedPrecision() {
        #expect((3.14159).fixed(fractionDigits: 2) == "3.14")
    }
}
