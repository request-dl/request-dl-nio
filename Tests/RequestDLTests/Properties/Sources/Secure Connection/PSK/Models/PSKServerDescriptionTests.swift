/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

@available(*, deprecated)
@RequestActor
class PSKServerDescriptionTests: XCTestCase {

    func test() async throws {
        // Given
        let hint = "password"
        let identity = "client"

        // When
        let sut = PSKServerDescription(
            serverHint: hint,
            clientHint: identity
        )

        // Then
        XCTAssertEqual(sut.serverHint, hint)
        XCTAssertEqual(sut.clientHint, identity)
    }
}
