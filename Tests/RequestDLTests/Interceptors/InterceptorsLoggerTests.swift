/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class InterceptorsLoggerTests: XCTestCase {

    func testConsole() async throws {
        // Given
        var outputLog = false

        Print.replace {
            outputLog = true
            Print.restoreRaise()
            print($0, separator: $1, terminator: $2)
        }

        // When
        _ = try await MockedTask(data: Data.init)
            .logInConsole(true)
            .result()

        // Then
        XCTAssertTrue(outputLog)
    }
}
