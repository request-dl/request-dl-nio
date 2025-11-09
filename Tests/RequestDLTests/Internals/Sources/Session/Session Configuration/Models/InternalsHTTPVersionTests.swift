/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import AsyncHTTPClient
@testable import RequestDL

struct InternalsHTTPVersionTests {

    @Test
    func version_whenHTTP1Only() {
        // Given
        let version = Internals.HTTPVersion.http1Only

        // When
        let sut = version.build()

        // Then
        #expect(sut == .http1Only)
    }

    @Test
    func version_whenAutomatic() {
        // Given
        let version = Internals.HTTPVersion.automatic

        // When
        let sut = version.build()

        // Then
        #expect(sut == .automatic)
    }

    @Test
    func version_whenEquals() {
        // Given
        let lhs = Internals.HTTPVersion.http1Only
        let rhs = Internals.HTTPVersion.http1Only

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func version_whenNotEquals() {
        // Given
        let lhs = Internals.HTTPVersion.http1Only
        let rhs = Internals.HTTPVersion.automatic

        // Then
        #expect(lhs != rhs)
    }
}
