/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
@RequestActor
class SecureConnectionContextTests: XCTestCase {

    func testContext_whenClient() async throws {
        // Given
        let sut: SecureConnectionContext = .client

        // Then
        XCTAssertEqual(sut, .client)
    }

    func testContext_whenServer() async throws {
        // Given
        let sut: SecureConnectionContext = .server

        // Then
        XCTAssertEqual(sut, .server)
    }
}
