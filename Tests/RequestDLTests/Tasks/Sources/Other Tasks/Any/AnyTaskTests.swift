/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

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
