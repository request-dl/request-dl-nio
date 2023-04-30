/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import AsyncHTTPClient
@testable import RequestDL

class InternalsTimeoutTests: XCTestCase {

    func testRedirect_whenDisallow() {
        // Given
        let redirect = Internals.RedirectConfiguration.disallow

        // When
        let sut = redirect.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: HTTPClient.Configuration.RedirectConfiguration.disallow)
        )
    }

    func testRedirect_whenFollow() {
        // Given
        let redirect = Internals.RedirectConfiguration.follow(max: 1_024, allowCycles: true)

        // When
        let sut = redirect.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: HTTPClient.Configuration.RedirectConfiguration.follow(max: 1_024, allowCycles: true))
        )
    }

    func testRedirect_whenEquals() {
        // Given
        let lhs = Internals.RedirectConfiguration.disallow
        let rhs = Internals.RedirectConfiguration.disallow

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func testRedirect_whenNotEquals() {
        // Given
        let lhs = Internals.RedirectConfiguration.disallow
        let rhs = Internals.RedirectConfiguration.follow(max: 1_024, allowCycles: true)

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
