//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

struct ReadingModeTests {

    @Test
    func readingByLength() async throws {
        // Given
        let length = 1_024

        // When
        let resolved = try await resolve(
            TestProperty {
                ReadingMode(length: length)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.readingMode == .length(length))
    }

    @Test
    func readingBySeparator() async throws {
        // Given
        let separator = Array(Data("\n".utf8))

        // When
        let resolved = try await resolve(
            TestProperty {
                ReadingMode(separator: separator)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.readingMode == .separator(separator))
    }

    @Test
    func readingByStringSeparator() async throws {
        // Given
        let separator = "\r\n"

        // When
        let resolved = try await resolve(
            TestProperty {
                ReadingMode(separator: separator)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.readingMode == .separator(Array(Data(separator.utf8))))
    }

    @Test func neverBody() async throws {
        // Given
        let property = ReadingMode(length: 1_024)

        // Then
        try await assertNever(property.body)
    }
}
