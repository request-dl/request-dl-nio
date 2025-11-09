/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import AsyncHTTPClient
@testable import RequestDL

struct InternalsDecompressionTests {

    @Test
    func decompression_whenDisabled() {
        // Given
        let decompression = Internals.Decompression.disabled

        // When
        let sut = decompression.build()

        // Then
        #expect(
            String(describing: sut) == String(
                describing: HTTPClient.Decompression.disabled
            )
        )
    }

    @Test
    func decompression_whenEnabled() {
        // Given
        let decompression = Internals.Decompression.enabled(.ratio(1_024))

        // When
        let sut = decompression.build()

        // Then
        #expect(
            String(describing: sut) == String(
                describing: HTTPClient.Decompression.enabled(limit: .ratio(1_024))
            )
        )
    }

    @Test
    func decompression_whenEquals() {
        // Given
        let lhs = Internals.Decompression.disabled
        let rhs = Internals.Decompression.disabled

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func decompression_whenNotEquals() {
        // Given
        let lhs = Internals.Decompression.disabled
        let rhs = Internals.Decompression.enabled(.none)

        // Then
        #expect(lhs != rhs)
    }
}
