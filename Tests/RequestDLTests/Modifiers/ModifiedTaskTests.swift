/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiedTaskTests: XCTestCase {

    struct Modified<Body: Task>: TaskModifier {

        let callback: () -> Void

        func task(_ task: Body) async throws -> Body.Element {
            callback()
            return try await task.result()
        }
    }

    func testModified() async throws {
        // Given
        var taskModified = false

        // When
        _ = try await MockedTask(data: Data.init)
            .modify(Modified {
                taskModified = true
            })
            .result()

        // Then
        XCTAssertTrue(taskModified)
    }
}
