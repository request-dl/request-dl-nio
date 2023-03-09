/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersContentTypeTests: XCTestCase {

    func testHeadersJsonContentType() async {
        let property = TestProperty(Headers.ContentType(.json))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testHeadersXmlContentType() async {
        let property = TestProperty(Headers.ContentType(.xml))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/xml")
    }

    func testHeadersFormDataContentType() async {
        let property = TestProperty(Headers.ContentType(.formData))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "form-data")
    }

    func testHeadersFormURLEncodedContentType() async {
        let property = TestProperty(Headers.ContentType(.formURLEncoded))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
    }

    func testHeadersTextContentType() async {
        let property = TestProperty(Headers.ContentType(.text))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain")
    }

    func testHeadersHtmlContentType() async {
        let property = TestProperty(Headers.ContentType(.html))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/html")
    }

    func testHeadersCssContentType() async {
        let property = TestProperty(Headers.ContentType(.css))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/css")
    }

    func testHeadersJavascriptContentType() async {
        let property = TestProperty(Headers.ContentType(.javascript))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
    }

    func testHeadersGifContentType() async {
        let property = TestProperty(Headers.ContentType(.gif))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/gif")
    }

    func testHeadersPngContentType() async {
        let property = TestProperty(Headers.ContentType(.png))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
    }

    func testHeadersJpegContentType() async {
        let property = TestProperty(Headers.ContentType(.jpeg))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
    }

    func testHeadersBmpContentType() async {
        let property = TestProperty(Headers.ContentType(.bmp))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/bmp")
    }

    func testHeadersWebpContentType() async {
        let property = TestProperty(Headers.ContentType(.webp))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/webp")
    }

    func testHeadersMidiContentType() async {
        let property = TestProperty(Headers.ContentType(.midi))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/midi")
    }

    func testHeadersMpegContentType() async {
        let property = TestProperty(Headers.ContentType(.mpeg))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/mpeg")
    }

    func testHeadersWavContentType() async {
        let property = TestProperty(Headers.ContentType(.wav))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
    }

    func testHeadersPdfContentType() async {
        let property = TestProperty(Headers.ContentType(.pdf))
        let (_, request) = await resolve(property)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/pdf")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.ContentType(.json)

        // Then
        try await assertNever(property.body)
    }
}
