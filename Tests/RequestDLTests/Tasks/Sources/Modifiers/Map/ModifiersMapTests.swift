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

struct ModifiersMapTests {

    @Test
    func map() async throws {
        // Given
        let output = 1

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(data: Data())
        }
        .collectData()
        .map { _ in output }
        .result()

        // Then
        #expect(result == output)
    }
}
