/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

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
