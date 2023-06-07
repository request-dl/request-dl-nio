/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class ModifiedTaskTests: XCTestCase {

    struct Modified<Content: RequestTask>: TaskModifier {

        let callback: @Sendable () -> Void

        func task(_ task: Content) async throws -> Content.Element {
            callback()
            return try await task.result()
        }
    }

    func testModified() async throws {
        // Given
        let taskModified = SendableBox(false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .modify(Modified {
            taskModified(true)
        })
        .result()

        // Then
        XCTAssertTrue(taskModified())
    }
}
