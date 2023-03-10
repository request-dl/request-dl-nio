/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HTTPMethodTests: XCTestCase {

    func testGetMethodRawValue() {
        XCTAssertEqual(HTTPMethod.get, "GET")
    }

    func testHeadMethodRawValue() {
        XCTAssertEqual(HTTPMethod.head, "HEAD")
    }

    func testPostMethodRawValue() {
        XCTAssertEqual(HTTPMethod.post, "POST")
    }

    func testPutMethodRawValue() {
        XCTAssertEqual(HTTPMethod.put, "PUT")
    }

    func testDeleteMethodRawValue() {
        XCTAssertEqual(HTTPMethod.delete, "DELETE")
    }

    func testConnectMethodRawValue() {
        XCTAssertEqual(HTTPMethod.connect, "CONNECT")
    }

    func testOptionsMethodRawValue() {
        XCTAssertEqual(HTTPMethod.options, "OPTIONS")
    }

    func testTraceMethodRawValue() {
        XCTAssertEqual(HTTPMethod.trace, "TRACE")
    }

    func testPatchMethodRawValue() {
        XCTAssertEqual(HTTPMethod.patch, "PATCH")
    }
}
