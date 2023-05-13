/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOPosix
@testable import RequestDL

class MultiThreadedEventLoopGroupTests: XCTestCase {

    func testMultiThreaded_whenObtainShared_shouldBeTheSameInSecondAccess() async throws {
        // Given
        let sut = MultiThreadedEventLoopGroup.shared

        // When
        let multiThreaded = MultiThreadedEventLoopGroup.shared

        // Then
        XCTAssertTrue(sut === multiThreaded)
    }
}
