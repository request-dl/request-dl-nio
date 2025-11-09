/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiedRequestTaskTests {

    struct Modified<Input: Sendable>: RequestTaskModifier {

        let callback: @Sendable () -> Void

        func body(_ task: Content) async throws -> Input {
            callback()
            return try await task.result()
        }
    }

    @Test
    func modified() async throws {
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
        #expect(taskModified())
    }
}
