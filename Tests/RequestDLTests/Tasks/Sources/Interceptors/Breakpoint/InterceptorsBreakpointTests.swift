/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

#if DEBUG
struct InterceptorsBreakpointTests {

    @Test
    func breakpoint() async throws {
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
        #expect(breakpointActivated())
    }
}
#endif
