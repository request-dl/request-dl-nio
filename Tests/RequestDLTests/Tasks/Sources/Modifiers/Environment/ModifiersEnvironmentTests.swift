/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersEnvironmentTests {

    struct NumberTask: RequestTask {

        @TaskEnvironment(\.number) var number

        func result() async throws -> Int {
            number
        }
    }

    @Test
    func environment_whenNotSet() async throws {
        // Given
        let numberTask = NumberTask()

        // When
        let value = try await numberTask.result()

        // Then
        #expect(value == 1)
    }

    @Test
    func environment_whenUpdatedWithValue() async throws {
        // Given
        let number = 2
        let numberTask = NumberTask()

        // When
        let value = try await numberTask
            .environment(\.number, number)
            .result()

        // Then
        #expect(value == number)
    }
}

private struct NumberKey: TaskEnvironmentKey {
    static let defaultValue = 1
}

extension TaskEnvironmentValues {

    fileprivate var number: Int {
        get { self[NumberKey.self] }
        set { self[NumberKey.self] = newValue }
    }
}
