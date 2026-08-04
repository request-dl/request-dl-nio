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

struct AnyTaskTests {

    @Test
    func anyTask() async throws {
        // Given
        let data = Data("123".utf8)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(data: data)
        }
        .collectData()
        .eraseToAnyTask()
        .result()

        // Then
        #expect(result.payload == data)
    }
}
