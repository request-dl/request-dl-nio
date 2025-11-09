/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOPosix
@testable import RequestDL

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
