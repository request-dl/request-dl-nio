/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class AuthorizationTokenTypeTests: XCTestCase {

    func testInitRawValueBasic() async throws {
        let type = Authorization.TokenType.basic
        XCTAssertEqual(type, .basic)
    }

    func testInitRawValueBearer() async throws {
        let type = Authorization.TokenType.bearer
        XCTAssertEqual(type, .bearer)
    }

    func testRawValueBasic() async throws {
        let type = Authorization.TokenType.basic
        XCTAssertEqual(type, "Basic")
    }

    func testRawValueBearer() async throws {
        let type = Authorization.TokenType.bearer
        XCTAssertEqual(type, "Bearer")
    }

    func testHashable() async throws {
        let sut: Set<Authorization.TokenType> = [.bearer, .bearer, .basic]

        XCTAssertEqual(sut, [.bearer, .basic])
    }

    func testToken_withStringLossless() async throws {
        // Given
        let token = Authorization.TokenType.basic

        // When
        let string = String(token)
        let losslessToken = Authorization.TokenType(string)

        // Then
        XCTAssertEqual(string, token.description)
        XCTAssertEqual(losslessToken, token)
    }
}
