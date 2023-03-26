/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class PathTests: XCTestCase {

    func testSinglePath() async throws {
        // Given
        let path = "api"
        let host = "google.com"

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(host)/\(path)"
        )
    }

    func testSingleInstanceWithMultiplePath() async throws {
        // Given
        let path = "api/v1/users/10/detail"
        let host = "google.com"

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(host)/\(path)"
        )
    }

    func testMultiplePath() async throws {
        // Given
        let path1 = "api"
        let path2 = "v1/"
        let path3 = "/users/10/detail"
        let host = "google.com"
        let characterSetRule = CharacterSet(charactersIn: "/")

        // When
        let (_, request) = try await resolve(TestProperty {
            BaseURL(host)
            Path(path1)
            Path(path2)
            Path(path3)
        })

        // Then
        let expectedPath2 = path2.trimmingCharacters(in: characterSetRule)
        let expectedPath3 = path3.trimmingCharacters(in: characterSetRule)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(host)/\(path1)/\(expectedPath2)/\(expectedPath3)"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Path("")

        // Then
        try await assertNever(property.body)
    }
}
