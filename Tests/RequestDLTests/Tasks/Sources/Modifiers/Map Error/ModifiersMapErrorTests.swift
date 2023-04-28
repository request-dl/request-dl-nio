/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class ModifiersMapErrorTests: XCTestCase {

    struct AnyError: Error {}

    struct ErrorTask<T>: Task {

        func result() async throws -> T {
            throw AnyError()
        }
    }

    func testMapError() async throws {
        // Given
        let output = 1
        let invalidOutput = 2

        // When
        let result = try await ErrorTask<Int>()
            .mapError {
                switch $0 {
                case is AnyError:
                    return output
                default:
                    return invalidOutput
                }
            }
            .result()

        // Then
        XCTAssertEqual(result, output)
    }
}
