/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersContentTypeTests: XCTestCase {

    func testHeadersJsonContentType() async throws {
        let property = TestProperty(Headers.ContentType(.json))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/json")
    }

    func testHeadersXmlContentType() async throws {
        let property = TestProperty(Headers.ContentType(.xml))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/xml")
    }

    func testHeadersFormDataContentType() async throws {
        let property = TestProperty(Headers.ContentType(.formData))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "form-data")
    }

    func testHeadersFormURLEncodedContentType() async throws {
        let property = TestProperty(Headers.ContentType(.formURLEncoded))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/x-www-form-urlencoded")
    }

    func testHeadersTextContentType() async throws {
        let property = TestProperty(Headers.ContentType(.text))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "text/plain")
    }

    func testHeadersHtmlContentType() async throws {
        let property = TestProperty(Headers.ContentType(.html))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "text/html")
    }

    func testHeadersCssContentType() async throws {
        let property = TestProperty(Headers.ContentType(.css))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "text/css")
    }

    func testHeadersJavascriptContentType() async throws {
        let property = TestProperty(Headers.ContentType(.javascript))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "text/javascript")
    }

    func testHeadersGifContentType() async throws {
        let property = TestProperty(Headers.ContentType(.gif))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/gif")
    }

    func testHeadersPngContentType() async throws {
        let property = TestProperty(Headers.ContentType(.png))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/png")
    }

    func testHeadersJpegContentType() async throws {
        let property = TestProperty(Headers.ContentType(.jpeg))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/jpeg")
    }

    func testHeadersBmpContentType() async throws {
        let property = TestProperty(Headers.ContentType(.bmp))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/bmp")
    }

    func testHeadersWebpContentType() async throws {
        let property = TestProperty(Headers.ContentType(.webp))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "image/webp")
    }

    func testHeadersMidiContentType() async throws {
        let property = TestProperty(Headers.ContentType(.midi))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "audio/midi")
    }

    func testHeadersMpegContentType() async throws {
        let property = TestProperty(Headers.ContentType(.mpeg))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "audio/mpeg")
    }

    func testHeadersWavContentType() async throws {
        let property = TestProperty(Headers.ContentType(.wav))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "audio/wav")
    }

    func testHeadersPdfContentType() async throws {
        let property = TestProperty(Headers.ContentType(.pdf))
        let (_, request) = try await resolve(property)
        XCTAssertEqual(request.headers.getValue(forKey: "Content-Type"), "application/pdf")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.ContentType(.json)

        // Then
        try await assertNever(property.body)
    }
}
