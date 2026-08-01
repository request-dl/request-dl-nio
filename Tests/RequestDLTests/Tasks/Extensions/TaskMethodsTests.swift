//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct TaskMethodsTests {

    @Test
    func pinging() async throws {
        // Given
        let data = Data()

        // When
        try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .ping(10)
    }
}
