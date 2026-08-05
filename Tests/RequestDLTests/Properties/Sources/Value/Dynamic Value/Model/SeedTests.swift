//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct SeedTests {

    @Test
    func seed_whenZero_shouldDescribeRawValue() {
        // Given
        let seed = Seed.zero

        // Then
        #expect(seed.description == "Seed(0)")
    }

    @Test
    func seed_whenNext_shouldIncrementRawValue() {
        // Given
        let seed = Seed(3)

        // When
        let next = seed.next()

        // Then
        #expect(next.description == "Seed(4)")
    }
}
