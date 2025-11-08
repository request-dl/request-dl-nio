/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct GroupTaskTests {

    @Test
    func groupTask() async throws {
        // Given
        let items = Array(0 ..< 10)

        // When
        let result = try await GroupTask(items) { index in
            MockedTask {
                BaseURL("localhost")
                Payload(data: Data("\(index)".utf8))
            }
            .collectData()
        }
        .result()

        // Then
        #expect(result.keys.count == items.count)
        #expect(items.allSatisfy {
            switch result[$0] {
            case .failure, .none:
                return false
            case .success(let result):
                return result.payload == Data("\($0)".utf8)
            }
        })
    }
}
