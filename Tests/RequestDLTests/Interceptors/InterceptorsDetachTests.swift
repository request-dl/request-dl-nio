/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class InterceptorsDetachTests: XCTestCase {

    func testDetach() async throws {
        // Given
        var taskDetached = false

        // When
        _ = try await MockedTask(data: Data.init)
            .detach { _ in
                taskDetached = true
            }
            .result()

        // Then
        XCTAssertTrue(taskDetached)
    }
}
