/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class AuthorizationTests: XCTestCase {

    func testAuthorizationWithTypeAndStringToken() async throws {
        // Given
        let auth = Authorization(.bearer, token: "myToken")

        // When
        let resolved = try await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(
            resolved.request.headers["Authorization"],
            ["Bearer myToken"]
        )
    }

    func testAuthorizationWithTypeAndLosslessStringToken() async throws {
        // Given
        let auth = Authorization(.bearer, token: 123)

        // When
        let resolved = try await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(
            resolved.request.headers["Authorization"],
            ["Bearer 123"]
        )
    }

    func testAuthorizationWithUsernameAndPassword() async throws {
        let auth = Authorization(username: "myUser", password: "myPassword")

        // When
        let resolved = try await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(
            resolved.request.headers["Authorization"],
            ["Basic bXlVc2VyOm15UGFzc3dvcmQ="]
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Authorization(.bearer, token: "123")

        // Then
        try await assertNever(property.body)
    }
}
