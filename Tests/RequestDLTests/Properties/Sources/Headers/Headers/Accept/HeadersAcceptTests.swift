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
            resolved.request.headers.getValue(forKey: "Accept"),
            "application/json"
        )
    }

    func testHeadersXmlAccept() async throws {
        let property = TestProperty(Headers.Accept(.xml))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "application/xml"
        )
    }

    func testHeadersFormDataAccept() async throws {
        let property = TestProperty(Headers.Accept(.formData))
        let resolved = try await resolve(property)

        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "form-data"
        )
    }

    func testHeadersFormURLEncodedAccept() async throws {
        let property = TestProperty(Headers.Accept(.formURLEncoded))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "application/x-www-form-urlencoded; charset=utf-8"
        )
    }

    func testHeadersTextAccept() async throws {
        let property = TestProperty(Headers.Accept(.text))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "text/plain"
        )
    }

    func testHeadersHtmlAccept() async throws {
        let property = TestProperty(Headers.Accept(.html))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "text/html"
        )
    }

    func testHeadersCssAccept() async throws {
        let property = TestProperty(Headers.Accept(.css))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "text/css"
        )
    }

    func testHeadersJavascriptAccept() async throws {
        let property = TestProperty(Headers.Accept(.javascript))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "text/javascript"
        )
    }

    func testHeadersGifAccept() async throws {
        let property = TestProperty(Headers.Accept(.gif))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "image/gif"
        )
    }

    func testHeadersPngAccept() async throws {
        let property = TestProperty(Headers.Accept(.png))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "image/png"
        )
    }

    func testHeadersJpegAccept() async throws {
        let property = TestProperty(Headers.Accept(.jpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "image/jpeg"
        )
    }

    func testHeadersBmpAccept() async throws {
        let property = TestProperty(Headers.Accept(.bmp))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "image/bmp"
        )
    }

    func testHeadersWebpAccept() async throws {
        let property = TestProperty(Headers.Accept(.webp))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "image/webp"
        )
    }

    func testHeadersMidiAccept() async throws {
        let property = TestProperty(Headers.Accept(.midi))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "audio/midi"
        )
    }

    func testHeadersMpegAccept() async throws {
        let property = TestProperty(Headers.Accept(.mpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "audio/mpeg"
        )
    }

    func testHeadersWavAccept() async throws {
        let property = TestProperty(Headers.Accept(.wav))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "audio/wav"
        )
    }

    func testHeadersPdfAccept() async throws {
        let property = TestProperty(Headers.Accept(.pdf))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers.getValue(forKey: "Accept"),
            "application/pdf"
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Accept(.json)

        // Then
        try await assertNever(property.body)
    }
}
