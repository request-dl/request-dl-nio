/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct AuthorizationTests {

    @Test
    func authorizationWithTypeAndStringToken() async throws {
        // Given
        let auth = Authorization(.bearer, token: "myToken")

        // When
        let resolved = try await resolve(TestProperty(auth))

        // Then
        #expect(
            resolved.request.headers["Authorization"],
            ["Bearer myToken"]
        )
    }

    @Test
    func authorizationWithTypeAndLosslessStringToken() async throws {
        // Given
        let auth = Authorization(.bearer, token: 123)

        // When
        let resolved = try await resolve(TestProperty(auth))

        // Then
        #expect(
            resolved.request.headers["Authorization"],
            ["Bearer 123"]
        )
    }

    @Test
    func authorizationWithUsernameAndPassword() async throws {
        let auth = Authorization(username: "myUser", password: "myPassword")

        // When
        let resolved = try await resolve(TestProperty(auth))

        // Then
        #expect(
            resolved.request.headers["Authorization"],
            ["Basic bXlVc2VyOm15UGFzc3dvcmQ="]
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Authorization(.bearer, token: "123")

        // Then
        try await assertNever(property.body)
    }
}
