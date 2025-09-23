/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import XCTest
@testable import RequestDL

class ModifiersEnvironmentTests: XCTestCase {

    struct NumberTask: RequestTask {

        @TaskEnvironment(\.number) var number

        func result() async throws -> Int {
            number
        }
    }

    func testEnvironment_whenNotSet() async throws {
        // Given
        let numberTask = NumberTask()

        // When
        let value = try await numberTask.result()

        // Then
        XCTAssertEqual(value, 1)
    }

    func testEnvironment_whenUpdatedWithValue() async throws {
        // Given
        let number = 2
        let numberTask = NumberTask()

        // When
        let value = try await numberTask
            .environment(\.number, number)
            .result()

        // Then
        XCTAssertEqual(value, number)
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
