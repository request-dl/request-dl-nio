/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class SecureConnectionTests: XCTestCase {

    func testSecure_whenSetMaxTLSVersion_shouldBeValid() async throws {
        // Given
        let maxVersion: RequestDL.TLSVersion = .v1_3

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(maximum: maxVersion)
        })

        let sut = session.configuration

        // Then
        XCTAssertEqual(sut.tlsMaximumSupportedProtocolVersion, maxVersion.build())
    }

    func testSecure_whenSetMinTLSVersion_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1_3

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minimum: minVersion)
        })

        let sut = session.configuration

        // Then
        XCTAssertEqual(sut.tlsMinimumSupportedProtocolVersion, minVersion.build())
    }

    func testSecure_whenUpdatesTLSVersions_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1
        let maxVersion: RequestDL.TLSVersion = .v1_3

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minimum: minVersion, maximum: maxVersion)
        })

        let sut = session.configuration

        // Then
        XCTAssertEqual(sut.tlsMinimumSupportedProtocolVersion, minVersion.build())
        XCTAssertEqual(sut.tlsMaximumSupportedProtocolVersion, maxVersion.build())
    }

    func testNeverBody() async throws {
        // Given
        let property = SecureConnection {}

        // Then
        try await assertNever(property.body)
    }
}
