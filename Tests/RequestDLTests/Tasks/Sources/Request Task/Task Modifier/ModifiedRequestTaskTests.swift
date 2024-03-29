/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiedRequestTaskTests: XCTestCase {

    struct Modified<Input: Sendable>: RequestTaskModifier {

        let callback: @Sendable () -> Void

        func body(_ task: Content) async throws -> Input {
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
        .modifier(Modified {
            taskModified(true)
        })
        .result()

        // Then
        XCTAssertTrue(taskModified())
    }
}
