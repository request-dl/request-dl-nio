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
        let breakpointActivated = InlineProperty(wrappedValue: false)

        try await Internals.Override.Raise.replace {
            breakpointActivated.wrappedValue = $0 == SIGTRAP
            return $0
        } perform: {
            // When
            _ = try await MockedTask {
                BaseURL("localhost")
            }
            .breakpoint()
            .result()

            // Then
            #expect(breakpointActivated.wrappedValue)
        }
    }
}
#endif
