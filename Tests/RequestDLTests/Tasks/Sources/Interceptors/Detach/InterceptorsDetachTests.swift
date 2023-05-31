/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InterceptorsDetachTests: XCTestCase {

    func testDetach() async throws {
        // Given
        let taskDetached = SendableBox(false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .detach { _ in
            taskDetached(true)
        }
        .result()

        // Then
        XCTAssertTrue(taskDetached())
    }
}
