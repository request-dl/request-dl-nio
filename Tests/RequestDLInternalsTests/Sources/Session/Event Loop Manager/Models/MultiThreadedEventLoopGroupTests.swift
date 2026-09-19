//
// See LICENSE for this package's licensing information.
//

// `NIOPosix.MultiThreadedEventLoopGroup` only exists under `canImport(NIOCore)`.
#if canImport(NIOCore)

import NIOPosix
import Testing

@testable import RequestDLInternals

struct MultiThreadedEventLoopGroupTests {

    @Test
    func multiThreaded_whenObtainShared_shouldBeTheSameInSecondAccess() async throws {
        // Given
        let sut = MultiThreadedEventLoopGroup.shared

        // When
        let multiThreaded = MultiThreadedEventLoopGroup.shared

        // Then
        #expect(sut === multiThreaded)
    }
}

#endif
