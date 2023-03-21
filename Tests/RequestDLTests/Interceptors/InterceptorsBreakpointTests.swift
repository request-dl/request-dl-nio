/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if DEBUG && canImport(Darwin)
final class InterceptorsBreakpointTests: XCTestCase {

    func testBreakpoint() async throws {
        // Given
        var breakpointActivated = false

        Raise.replace {
            breakpointActivated = $0 == SIGTRAP
            Raise.restoreRaise()
            return $0
        }

        // When
        _ = try await MockedTask(data: Data.init)
            .breakpoint()
            .result()

        // Then
        XCTAssertTrue(breakpointActivated)
    }
}
#endif
