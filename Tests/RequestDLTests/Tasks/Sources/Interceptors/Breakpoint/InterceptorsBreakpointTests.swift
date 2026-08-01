//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
