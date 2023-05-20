/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class HeadersContentTypeTests: XCTestCase {

    func testHeadersJsonContentType() async throws {
        let property = TestProperty(Headers.ContentType(.json))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["application/json"])
    }

    func testHeadersXmlContentType() async throws {
        let property = TestProperty(Headers.ContentType(.xml))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["application/xml"])
    }

    func testHeadersFormDataContentType() async throws {
        let property = TestProperty(Headers.ContentType(.formData))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["form-data"])
    }

    func testHeadersFormURLEncodedContentType() async throws {
        let property = TestProperty(Headers.ContentType(.formURLEncoded))
        let resolved = try await resolve(property)
        XCTAssertEqual(
            resolved.request.headers["Content-Type"],
            ["application/x-www-form-urlencoded"]
        )
    }

    func testHeadersTextContentType() async throws {
        let property = TestProperty(Headers.ContentType(.text))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["text/plain"])
    }

    func testHeadersHtmlContentType() async throws {
        let property = TestProperty(Headers.ContentType(.html))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["text/html"])
    }

    func testHeadersCssContentType() async throws {
        let property = TestProperty(Headers.ContentType(.css))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["text/css"])
    }

    func testHeadersJavascriptContentType() async throws {
        let property = TestProperty(Headers.ContentType(.javascript))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["text/javascript"])
    }

    func testHeadersGifContentType() async throws {
        let property = TestProperty(Headers.ContentType(.gif))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/gif"])
    }

    func testHeadersPngContentType() async throws {
        let property = TestProperty(Headers.ContentType(.png))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/png"])
    }

    func testHeadersJpegContentType() async throws {
        let property = TestProperty(Headers.ContentType(.jpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/jpeg"])
    }

    func testHeadersBmpContentType() async throws {
        let property = TestProperty(Headers.ContentType(.bmp))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/bmp"])
    }

    func testHeadersWebpContentType() async throws {
        let property = TestProperty(Headers.ContentType(.webp))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["image/webp"])
    }

    func testHeadersMidiContentType() async throws {
        let property = TestProperty(Headers.ContentType(.midi))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["audio/midi"])
    }

    func testHeadersMpegContentType() async throws {
        let property = TestProperty(Headers.ContentType(.mpeg))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["audio/mpeg"])
    }

    func testHeadersWavContentType() async throws {
        let property = TestProperty(Headers.ContentType(.wav))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["audio/wav"])
    }

    func testHeadersPdfContentType() async throws {
        let property = TestProperty(Headers.ContentType(.pdf))
        let resolved = try await resolve(property)
        XCTAssertEqual(resolved.request.headers["Content-Type"], ["application/pdf"])
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.ContentType(.json)

        // Then
        try await assertNever(property.body)
    }
}
