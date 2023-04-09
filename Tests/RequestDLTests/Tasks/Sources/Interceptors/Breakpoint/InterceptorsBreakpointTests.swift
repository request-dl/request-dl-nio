/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if DEBUG
final class InterceptorsBreakpointTests: XCTestCase {

    func testBreakpoint() async throws {
        // Given
        var breakpointActivated = false

        SwiftOverride.Raise.replace {
            breakpointActivated = $0 == SIGTRAP
            SwiftOverride.Raise.restoreRaise()
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
