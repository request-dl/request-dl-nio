/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class RequestMethodTests: XCTestCase {

    func testGetHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.get))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "GET")
    }

    func testHeadHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.head))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "HEAD")
    }

    func testPostHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.post))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "POST")
    }

    func testPutHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.put))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "PUT")
    }

    func testDeleteHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.delete))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "DELETE")
    }

    func testConnectHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.connect))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "CONNECT")
    }

    func testOptionsHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.options))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "OPTIONS")
    }

    func testTraceHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.trace))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "TRACE")
    }

    func testPatchHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.patch))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.method, "PATCH")
    }

    func testNeverBody() async throws {
        // Given
        let property = RequestMethod(.get)

        // Then
        try await assertNever(property.body)
    }
}
