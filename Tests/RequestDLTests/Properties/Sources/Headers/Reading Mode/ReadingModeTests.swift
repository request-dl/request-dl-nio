//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
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

    @Test
    func readingBySeparatorWithMaximumItemSize() async throws {
        // Given
        let separator = Array(Data("\n".utf8))

        // When
        let resolved = try await resolve(
            TestProperty {
                ReadingMode(separator: separator, maximumItemSize: 4_096)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.readingMode == .separator(separator, maximumItemSize: 4_096))
    }

    @Test
    func readingByStringSeparatorWithMaximumItemSize() async throws {
        // When
        let resolved = try await resolve(
            TestProperty {
                ReadingMode(separator: "\r\n", maximumItemSize: 64)
            }
        )

        // Then
        #expect(
            resolved.requestConfiguration.readingMode
                == .separator(Array(Data("\r\n".utf8)), maximumItemSize: 64)
        )
    }

    /// The limit is part of what identifies the mode: the same separator without one is another.
    @Test
    func readingBySeparator_withAndWithoutMaximumItemSize_areDifferentModes() {
        #expect(
            Internals.DownloadStep.ReadingMode.separator([10])
                != .separator([10], maximumItemSize: 10)
        )
    }

    @Test func neverBody() async throws {
        // Given
        let property = ReadingMode(length: 1_024)

        // Then
        try await assertNever(property.body)
    }

    // Swift Testing's exit tests need to spawn a real child process, which only macOS and Linux
    // support here: iOS/tvOS/watchOS/visionOS (device or Simulator) don't allow it, so
    // `#expect(processExitsWith:)` isn't even available to call there.
    #if os(macOS) || os(Linux)
    /// A non-positive length can never make progress reading the body (see `ReadingMode.init`'s
    /// own doc comment), so construction traps instead of silently producing an empty response.
    @Test
    func initWithZeroLength_traps() async {
        // The exit-test closure below runs in a spawned child process, so it cannot capture
        // anything from this scope (a parameterized `length` included). The literal has to be
        // written directly inside it.
        await #expect(processExitsWith: .failure) {
            _ = ReadingMode(length: 0)
        }
    }

    @Test
    func initWithNegativeLength_traps() async {
        await #expect(processExitsWith: .failure) {
            _ = ReadingMode(length: -1)
        }
    }
    #endif
}
