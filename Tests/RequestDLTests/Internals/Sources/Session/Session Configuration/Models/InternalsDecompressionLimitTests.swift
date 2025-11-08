/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOHTTPCompression
@testable import RequestDL

struct InternalsDecompressionLimitTests {

    @Test
    func limit_whenNone() {
        // Given
        let limit = Internals.Decompression.Limit.none

        // When
        let sut = limit.build()

        // Then
        #expect(
            String(describing: sut),
            String(describing: NIOHTTPDecompression.DecompressionLimit.none)
        )
    }

    @Test
    func limit_whenSize() {
        // Given
        let limit = Internals.Decompression.Limit.size(128)

        // When
        let sut = limit.build()

        // Then
        #expect(
            String(describing: sut),
            String(describing: NIOHTTPDecompression.DecompressionLimit.size(128))
        )
    }

    @Test
    func limit_whenRatio() {
        // Given
        let limit = Internals.Decompression.Limit.ratio(1_024)

        // When
        let sut = limit.build()

        // Then
        #expect(
            String(describing: sut),
            String(describing: NIOHTTPDecompression.DecompressionLimit.ratio(1_024))
        )
    }

    @Test
    func limit_whenEquals() {
        // Given
        let lhs = Internals.Decompression.Limit.ratio(1)
        let rhs = Internals.Decompression.Limit.ratio(1)

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func limit_whenNotEquals() {
        // Given
        let lhs = Internals.Decompression.Limit.none
        let rhs = Internals.Decompression.Limit.ratio(1)

        // Then
        #expect(lhs != rhs)
    }
}
