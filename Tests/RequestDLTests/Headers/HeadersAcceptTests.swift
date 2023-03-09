/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersAcceptTests: XCTestCase {

    func testHeadersJsonAccept() async {
        let property = TestProperty(Headers.Accept(.json))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testHeadersXmlAccept() async {
        let property = TestProperty(Headers.Accept(.xml))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/xml")
    }

    func testHeadersFormDataAccept() async {
        let property = TestProperty(Headers.Accept(.formData))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "form-data")
    }

    func testHeadersFormURLEncodedAccept() async {
        let property = TestProperty(Headers.Accept(.formURLEncoded))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/x-www-form-urlencoded")
    }

    func testHeadersTextAccept() async {
        let property = TestProperty(Headers.Accept(.text))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/plain")
    }

    func testHeadersHtmlAccept() async {
        let property = TestProperty(Headers.Accept(.html))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
    }

    func testHeadersCssAccept() async {
        let property = TestProperty(Headers.Accept(.css))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/css")
    }

    func testHeadersJavascriptAccept() async {
        let property = TestProperty(Headers.Accept(.javascript))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/javascript")
    }

    func testHeadersGifAccept() async {
        let property = TestProperty(Headers.Accept(.gif))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/gif")
    }

    func testHeadersPngAccept() async {
        let property = TestProperty(Headers.Accept(.png))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/png")
    }

    func testHeadersJpegAccept() async {
        let property = TestProperty(Headers.Accept(.jpeg))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg")
    }

    func testHeadersBmpAccept() async {
        let property = TestProperty(Headers.Accept(.bmp))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/bmp")
    }

    func testHeadersWebpAccept() async {
        let property = TestProperty(Headers.Accept(.webp))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/webp")
    }

    func testHeadersMidiAccept() async {
        let property = TestProperty(Headers.Accept(.midi))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/midi")
    }

    func testHeadersMpegAccept() async {
        let property = TestProperty(Headers.Accept(.mpeg))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/mpeg")
    }

    func testHeadersWavAccept() async {
        let property = TestProperty(Headers.Accept(.wav))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/wav")
    }

    func testHeadersPdfAccept() async {
        let property = TestProperty(Headers.Accept(.pdf))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/pdf")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Accept(.json)

        // Then
        try await assertNever(property.body)
    }
}
