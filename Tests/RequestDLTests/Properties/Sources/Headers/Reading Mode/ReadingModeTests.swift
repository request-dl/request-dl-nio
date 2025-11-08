/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ReadingModeTests {

    @Test
    func readingByLength() async throws {
        // Given
        let length = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            ReadingMode(length: length)
        })

        // Then
        #expect(resolved.request.readingMode == .length(length))
    }

    @Test
    func readingBySeparator() async throws {
        // Given
        let separator = Array(Data("\n".utf8))

        // When
        let resolved = try await resolve(TestProperty {
            ReadingMode(separator: separator)
        })

        // Then
        #expect(resolved.request.readingMode == .separator(separator))
    }
}
