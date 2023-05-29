/*
 See LICENSE for this package's licensing information.
 */

import XCTest
@testable import RequestDL

class AcceptHeaderTests: XCTestCase {

    func testHeadersJsonAccept() async throws {
        let property = TestProperty(AcceptHeader(.json))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/json"]
        )
    }

    func testHeadersXmlAccept() async throws {
        let property = TestProperty(AcceptHeader(.xml))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/xml"]
        )
    }

    func testHeadersFormDataAccept() async throws {
        let property = TestProperty(AcceptHeader(.formData))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["form-data"]
        )
    }

    func testHeadersFormURLEncodedAccept() async throws {
        let property = TestProperty(AcceptHeader(.formURLEncoded))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/x-www-form-urlencoded"]
        )
    }

    func testHeadersTextAccept() async throws {
        let property = TestProperty(AcceptHeader(.text))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/plain"]
        )
    }

    func testHeadersHtmlAccept() async throws {
        let property = TestProperty(AcceptHeader(.html))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/html"]
        )
    }

    func testHeadersCssAccept() async throws {
        let property = TestProperty(AcceptHeader(.css))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/css"]
        )
    }

    func testHeadersJavascriptAccept() async throws {
        let property = TestProperty(AcceptHeader(.javascript))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/javascript"]
        )
    }

    func testHeadersGifAccept() async throws {
        let property = TestProperty(AcceptHeader(.gif))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/gif"]
        )
    }

    func testHeadersPngAccept() async throws {
        let property = TestProperty(AcceptHeader(.png))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/png"]
        )
    }

    func testHeadersJpegAccept() async throws {
        let property = TestProperty(AcceptHeader(.jpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/jpeg"]
        )
    }

    func testHeadersBmpAccept() async throws {
        let property = TestProperty(AcceptHeader(.bmp))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/bmp"]
        )
    }

    func testHeadersWebpAccept() async throws {
        let property = TestProperty(AcceptHeader(.webp))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/webp"]
        )
    }

    func testHeadersMidiAccept() async throws {
        let property = TestProperty(AcceptHeader(.midi))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["audio/midi"]
        )
    }

    func testHeadersMpegAccept() async throws {
        let property = TestProperty(AcceptHeader(.mpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["audio/mpeg"]
        )
    }

    func testHeadersWavAccept() async throws {
        let property = TestProperty(AcceptHeader(.wav))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["audio/wav"]
        )
    }

    func testHeadersPdfAccept() async throws {
        let property = TestProperty(AcceptHeader(.pdf))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/pdf"]
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = AcceptHeader(.json)

        // Then
        try await assertNever(property.body)
    }
}
