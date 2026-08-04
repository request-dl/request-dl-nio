//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif

// `SIGTRAP` is a libc signal constant, not a `Foundation` one — it comes from whichever of
// these the platform provides, matching `Internals.Override.Raise`'s own imports.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WinSDK)
import WinSDK
#endif

// `.breakpoint()` (`Interceptors.Breakpoint`) only exists where `signal_h` is importable —
// effectively Darwin, whose SDK auto-modularizes system headers this way. Glibc exposes
// `signal.h`'s declarations through the single `Glibc` umbrella module instead, so this test's
// only subject does not exist to call on Linux.
#if canImport(signal_h)
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
#endif
