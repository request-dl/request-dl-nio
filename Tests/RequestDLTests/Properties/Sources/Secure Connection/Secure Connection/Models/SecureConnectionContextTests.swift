/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class SecureConnectionContextTests: XCTestCase {

    func testContext_whenClient_shouldBeClient() async throws {
        // Given
        let context: SecureConnectionContext = .client

        // When
        let sut = context.build()

        // Then
        XCTAssertEqual(sut, .client)
    }

    func testContext_whenServer_shouldBeServer() async throws {
        // Given
        let context: SecureConnectionContext = .server

        // When
        let sut = context.build()

        // Then
        XCTAssertEqual(sut, .server)
    }
}
