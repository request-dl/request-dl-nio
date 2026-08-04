//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct StringShiftedTests {

    @Test
    func debugShiftLines_withPositiveShifting_indentsEachLine() {
        // Given
        let text = "a\nb"

        // When
        let sut = text.debug_shiftLines(2)

        // Then
        #expect(sut == "  a\n  b")
    }

    @Test
    func debugShiftLines_withZeroShifting_leavesLinesUnindented() {
        // Given
        let text = "a\nb"

        // When
        let sut = text.debug_shiftLines(.zero)

        // Then
        #expect(sut == "a\nb")
    }

    @Test
    func debugShiftLines_withNegativeShifting_leavesLinesUnindented() {
        // Given
        let text = "a\nb"

        // When
        let sut = text.debug_shiftLines(-1)

        // Then
        #expect(sut == "a\nb")
    }
}
