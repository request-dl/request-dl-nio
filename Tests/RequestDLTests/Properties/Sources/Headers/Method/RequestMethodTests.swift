/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class RequestMethodTests: XCTestCase {

    func testGetHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.get))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "GET")
    }

    func testHeadHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.head))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "HEAD")
    }

    func testPostHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.post))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "POST")
    }

    func testPutHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.put))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "PUT")
    }

    func testDeleteHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.delete))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "DELETE")
    }

    func testConnectHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.connect))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "CONNECT")
    }

    func testOptionsHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.options))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "OPTIONS")
    }

    func testTraceHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.trace))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "TRACE")
    }

    func testPatchHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.patch))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.method, "PATCH")
    }

    func testNeverBody() async throws {
        // Given
        let property = RequestMethod(.get)

        // Then
        try await assertNever(property.body)
    }
}
