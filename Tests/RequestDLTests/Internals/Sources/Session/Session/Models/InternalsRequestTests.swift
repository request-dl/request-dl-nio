/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
@testable import RequestDL

@RequestActor
class InternalsRequestTests: XCTestCase {

    private var request: Internals.Request!

    override func setUp() async throws {
        try await super.setUp()
        request = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        request = nil
    }

    func testRequest_whenInitURL_shouldBeEqual() async throws {
        // Given
        let url = "https://google.com"

        // When
        request.baseURL = url

        // Then
        XCTAssertEqual(request.url, url)
    }

    func testRequest_whenMethodIsAssign_shouldBeEqual() async throws {
        // Given
        let method = "POST"

        // When
        request.method = method

        // Then
        XCTAssertEqual(request.method, method)
    }

    func testRequest_whenHeadersAreSet_shouldContainsValues() async throws {
        // Given
        let key1 = "Content-Type"
        let value1 = "application/json"

        let key2 = "Accept"
        let value2 = "text/html"

        // When
        request.headers.setValue(value1, forKey: key1)
        request.headers.setValue(value2, forKey: key2)

        // Then
        XCTAssertEqual(request.headers.count, 2)
        XCTAssertEqual(request.headers.getValue(forKey: key1), value1)
        XCTAssertEqual(request.headers.getValue(forKey: key2), value2)
    }

    func testRequest_whenSetReadingMode_shouldBeEqual() async throws {
        // Given
        let readingMode = Internals.Response.ReadingMode.separator([70])

        // When
        request.readingMode = readingMode

        // Then
        XCTAssertEqual(request.readingMode, readingMode)
    }

    func testRequest_whenUnsetReadingMode() async throws {
        // Then
        XCTAssertEqual(request.readingMode, .length(1_024))
    }
}
