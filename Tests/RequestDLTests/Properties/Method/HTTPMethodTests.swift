/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HTTPMethodTests: XCTestCase {

    func testGetMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.get, "GET")
    }

    func testHeadMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.head, "HEAD")
    }

    func testPostMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.post, "POST")
    }

    func testPutMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.put, "PUT")
    }

    func testDeleteMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.delete, "DELETE")
    }

    func testConnectMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.connect, "CONNECT")
    }

    func testOptionsMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.options, "OPTIONS")
    }

    func testTraceMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.trace, "TRACE")
    }

    func testPatchMethodRawValue() async throws {
        XCTAssertEqual(HTTPMethod.patch, "PATCH")
    }
}
