/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class GroupTaskTests: XCTestCase {

    func testGroupTask() async throws {
        // Given
        let items = Array(0 ..< 10)

        // When
        let result = try await GroupTask(items) { index in
            MockedTask {
                Data("\(index)".utf8)
            }
        }
        .result()

        // Then
        XCTAssertEqual(result.keys.count, items.count)
        XCTAssertTrue(items.allSatisfy {
            switch result[$0] {
            case .failure, .none:
                return false
            case .success(let result):
                return result.payload == Data("\($0)".utf8)
            }
        })
    }
}