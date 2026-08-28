//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

@Suite(.concurrent(2), .nonFatalWatchdog)
struct URLExtensionsTests {

    @Test
    func writeThenReadDataRoundTrips() async throws {
        try await withTemporaryFileURL("payload.bin") { url in
            // Given
            let data = Data("hello world".utf8)

            // When
            try await url.write(data)
            let readBack = try await url.readData()

            // Then
            #expect(readBack == data)
        }
    }

    @Test
    func writeReplacesExistingContent() async throws {
        try await withTemporaryFileURL("payload.bin") { url in
            // Given
            try await url.write(Data("first".utf8))

            // When
            try await url.write(Data("second".utf8))
            let readBack = try await url.readData()

            // Then
            #expect(readBack == Data("second".utf8))
        }
    }
}
