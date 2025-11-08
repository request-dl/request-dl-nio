/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct AuthorizationTokenTypeTests {

    @Test
    func initRawValueBasic() async throws {
        let type = Authorization.TokenType.basic
        #expect(type == .basic)
    }

    @Test
    func initRawValueBearer() async throws {
        let type = Authorization.TokenType.bearer
        #expect(type == .bearer)
    }

    @Test
    func rawValueBasic() async throws {
        let type = Authorization.TokenType.basic
        #expect(type == "Basic")
    }

    @Test
    func rawValueBearer() async throws {
        let type = Authorization.TokenType.bearer
        #expect(type == "Bearer")
    }

    @Test
    func hashable() async throws {
        let sut: Set<Authorization.TokenType> = [.bearer, .bearer, .basic]

        #expect(sut, [.bearer == .basic])
    }

    @Test
    func token_withStringLossless() async throws {
        // Given
        let token = Authorization.TokenType.basic

        // When
        let string = String(token)
        let losslessToken = Authorization.TokenType(string)

        // Then
        #expect(string == token.description)
        #expect(losslessToken == token)
    }
}
