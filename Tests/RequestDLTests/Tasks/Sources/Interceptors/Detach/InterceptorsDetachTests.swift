/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InterceptorsDetachTests {

    @Test
    func detach() async throws {
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
        #expect(taskDetached())
    }
}
