/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersExtractPayloadTests {

    @Test
    func extractPayload() async throws {
        // Given
        let data = Data("--".utf8)

        // When
        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .extractPayload()
        .result()

        // Then
        #expect(result == data)
    }
}
