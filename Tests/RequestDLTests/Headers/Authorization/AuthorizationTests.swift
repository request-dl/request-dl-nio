/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class AuthorizationTests: XCTestCase {

    func testAuthorizationWithTypeAndToken() async {
        // Given
        let auth = Authorization(.bearer, token: "myToken")

        // When
        let (_, request) = await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer myToken")
    }

    func testAuthorizationWithUsernameAndPassword() async {
        let auth = Authorization(username: "myUser", password: "myPassword")

        // When
        let (_, request) = await resolve(TestProperty(auth))

        // Then
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic bXlVc2VyOm15UGFzc3dvcmQ=")
    }

    func testNeverBody() async throws {
        // Given
        let property = Authorization(.bearer, token: "123")

        // Then
        try await assertNever(property.body)
    }
}