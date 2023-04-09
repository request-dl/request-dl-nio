/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersAcceptTests: XCTestCase {

    func testHeadersJsonAccept() async throws {
        let property = TestProperty(Headers.Accept(.json))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "application/json")
    }

    func testHeadersXmlAccept() async throws {
        let property = TestProperty(Headers.Accept(.xml))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "application/xml")
    }

    func testHeadersFormDataAccept() async throws {
        let property = TestProperty(Headers.Accept(.formData))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "form-data")
    }

    func testHeadersFormURLEncodedAccept() async throws {
        let property = TestProperty(Headers.Accept(.formURLEncoded))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "application/x-www-form-urlencoded")
    }

    func testHeadersTextAccept() async throws {
        let property = TestProperty(Headers.Accept(.text))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/plain")
    }

    func testHeadersHtmlAccept() async throws {
        let property = TestProperty(Headers.Accept(.html))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/html")
    }

    func testHeadersCssAccept() async throws {
        let property = TestProperty(Headers.Accept(.css))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/css")
    }

    func testHeadersJavascriptAccept() async throws {
        let property = TestProperty(Headers.Accept(.javascript))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "text/javascript")
    }

    func testHeadersGifAccept() async throws {
        let property = TestProperty(Headers.Accept(.gif))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/gif")
    }

    func testHeadersPngAccept() async throws {
        let property = TestProperty(Headers.Accept(.png))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/png")
    }

    func testHeadersJpegAccept() async throws {
        let property = TestProperty(Headers.Accept(.jpeg))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/jpeg")
    }

    func testHeadersBmpAccept() async throws {
        let property = TestProperty(Headers.Accept(.bmp))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/bmp")
    }

    func testHeadersWebpAccept() async throws {
        let property = TestProperty(Headers.Accept(.webp))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "image/webp")
    }

    func testHeadersMidiAccept() async throws {
        let property = TestProperty(Headers.Accept(.midi))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "audio/midi")
    }

    func testHeadersMpegAccept() async throws {
        let property = TestProperty(Headers.Accept(.mpeg))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "audio/mpeg")
    }

    func testHeadersWavAccept() async throws {
        let property = TestProperty(Headers.Accept(.wav))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "audio/wav")
    }

    func testHeadersPdfAccept() async throws {
        let property = TestProperty(Headers.Accept(.pdf))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Accept"), "application/pdf")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Accept(.json)

        // Then
        try await assertNever(property.body)
    }
}
