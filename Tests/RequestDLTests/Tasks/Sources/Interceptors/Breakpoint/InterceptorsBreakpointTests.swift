/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

#if DEBUG
class InterceptorsBreakpointTests: XCTestCase {

    func testBreakpoint() async throws {
        // Given
        let breakpointActivated = SendableBox(false)

        Internals.Override.Raise.replace {
            breakpointActivated($0 == SIGTRAP)
            Internals.Override.Raise.restore()
            return $0
        }

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .breakpoint()
        .result()

        // Then
        XCTAssertTrue(breakpointActivated())
    }
}
#endif
