/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import AsyncHTTPClient
@testable import RequestDL

struct InternalsRedirectConfigurationTests {

    @Test
    func redirect_whenDisallow() {
        // Given
        let redirect = Internals.RedirectConfiguration.disallow

        // When
        let sut = redirect.build()

        // Then
        #expect(
            String(describing: sut) == String(
                describing: HTTPClient.Configuration.RedirectConfiguration.disallow
            )
        )
    }

    @Test
    func redirect_whenFollow() {
        // Given
        let redirect = Internals.RedirectConfiguration.follow(max: 1_024, allowCycles: true)

        // When
        let sut = redirect.build()

        // Then
        #expect(
            String(describing: sut) == String(
                describing: HTTPClient.Configuration.RedirectConfiguration.follow(max: 1_024, allowCycles: true)
            )
        )
    }

    @Test
    func redirect_whenEquals() {
        // Given
        let lhs = Internals.RedirectConfiguration.disallow
        let rhs = Internals.RedirectConfiguration.disallow

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func redirect_whenNotEquals() {
        // Given
        let lhs = Internals.RedirectConfiguration.disallow
        let rhs = Internals.RedirectConfiguration.follow(max: 1_024, allowCycles: true)

        // Then
        #expect(lhs != rhs)
    }
}
