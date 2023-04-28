/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class AuthorizationTests: XCTestCase {

    func testAuthorizationWithTypeAndToken() async throws {
        // Given
        let auth = Authorization(.bearer, token: "myToken")

        // When
        let (_, request) = try await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(request.headers.getValue(forKey: "Authorization"), "Bearer myToken")
    }

    func testAuthorizationWithUsernameAndPassword() async throws {
        let auth = Authorization(username: "myUser", password: "myPassword")

        // When
        let (_, request) = try await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(request.headers.getValue(forKey: "Authorization"), "Basic bXlVc2VyOm15UGFzc3dvcmQ=")
    }

    func testNeverBody() async throws {
        // Given
        let property = Authorization(.bearer, token: "123")

        // Then
        try await assertNever(property.body)
    }
}
