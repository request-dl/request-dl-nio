//
// See LICENSE for this package's licensing information.
//

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

    @Test func neverBody() async throws {
        // Given
        let property = ReadingMode(length: 1_024)

        // Then
        try await assertNever(property.body)
    }

    /// Regression coverage for a length of zero (or negative) silently discarding the entire
    /// response body: `Internals.DownloadBuffer._appendByLength` computes each read as
    /// `min(receivedBytes, length - buffer.readableBytes)`, `0` whenever `length <= 0`, and a
    /// zero-length read is never satisfied (`Internals.Buffer.readData(0)` always returns `nil`)
    /// -- so every chunk would be silently dropped forever, with no error anywhere, and a
    /// request that should have real content instead completing normally with an empty body.
    /// `ReadingMode(length:)` now traps on construction instead, well before any of that has a
    /// chance to happen.
    @Test
    func initWithZeroLength_traps() async {
        // The exit-test closure below runs in a spawned child process and so cannot capture
        // anything from this scope (a parameterized `length` included) -- the literal has to be
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
}
