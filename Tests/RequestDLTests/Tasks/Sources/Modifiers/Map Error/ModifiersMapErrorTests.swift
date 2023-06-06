/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersMapErrorTests: XCTestCase {

    struct AnyError: Error {}

    func testMapError() async throws {
        // Given
        let output = 1
        let invalidOutput = 2

        // When
        let result = try await MockedTask(content: {
            AsyncProperty {
                throw AnyError()
            }
        })
        .map { _ in Int.zero }
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
