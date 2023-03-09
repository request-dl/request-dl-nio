/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class AuthorizationTokenTypeTests: XCTestCase {

    func testInitRawValueBasic() {
        let type = Authorization.TokenType.basic
        XCTAssertEqual(type, .basic)
    }

    func testInitRawValueBearer() {
        let type = Authorization.TokenType.bearer
        XCTAssertEqual(type, .bearer)
    }

    func testRawValueBasic() {
        let type = Authorization.TokenType.basic
        XCTAssertEqual(type, "Basic")
    }

    func testRawValueBearer() {
        let type = Authorization.TokenType.bearer
        XCTAssertEqual(type, "Bearer")
    }
}
