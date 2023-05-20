/*
 See LICENSE for this package's licensing information.
 */

import XCTest
@testable import RequestDL

class HeadersAcceptTests: XCTestCase {

    func testHeadersJsonAccept() async throws {
        let property = TestProperty(Headers.Accept(.json))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/json"]
        )
    }

    func testHeadersXmlAccept() async throws {
        let property = TestProperty(Headers.Accept(.xml))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/xml"]
        )
    }

    func testHeadersFormDataAccept() async throws {
        let property = TestProperty(Headers.Accept(.formData))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["form-data"]
        )
    }

    func testHeadersFormURLEncodedAccept() async throws {
        let property = TestProperty(Headers.Accept(.formURLEncoded))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/x-www-form-urlencoded"]
        )
    }

    func testHeadersTextAccept() async throws {
        let property = TestProperty(Headers.Accept(.text))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/plain"]
        )
    }

    func testHeadersHtmlAccept() async throws {
        let property = TestProperty(Headers.Accept(.html))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/html"]
        )
    }

    func testHeadersCssAccept() async throws {
        let property = TestProperty(Headers.Accept(.css))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/css"]
        )
    }

    func testHeadersJavascriptAccept() async throws {
        let property = TestProperty(Headers.Accept(.javascript))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["text/javascript"]
        )
    }

    func testHeadersGifAccept() async throws {
        let property = TestProperty(Headers.Accept(.gif))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/gif"]
        )
    }

    func testHeadersPngAccept() async throws {
        let property = TestProperty(Headers.Accept(.png))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/png"]
        )
    }

    func testHeadersJpegAccept() async throws {
        let property = TestProperty(Headers.Accept(.jpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/jpeg"]
        )
    }

    func testHeadersBmpAccept() async throws {
        let property = TestProperty(Headers.Accept(.bmp))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/bmp"]
        )
    }

    func testHeadersWebpAccept() async throws {
        let property = TestProperty(Headers.Accept(.webp))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["image/webp"]
        )
    }

    func testHeadersMidiAccept() async throws {
        let property = TestProperty(Headers.Accept(.midi))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["audio/midi"]
        )
    }

    func testHeadersMpegAccept() async throws {
        let property = TestProperty(Headers.Accept(.mpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["audio/mpeg"]
        )
    }

    func testHeadersWavAccept() async throws {
        let property = TestProperty(Headers.Accept(.wav))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["audio/wav"]
        )
    }

    func testHeadersPdfAccept() async throws {
        let property = TestProperty(Headers.Accept(.pdf))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Accept"],
            ["application/pdf"]
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Accept(.json)

        // Then
        try await assertNever(property.body)
    }
}
