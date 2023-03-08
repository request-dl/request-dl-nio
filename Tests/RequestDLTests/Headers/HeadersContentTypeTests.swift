//
//  HeadersContentTypeTests.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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
        let type = Headers.ContentType.self

        // Then
        XCTAssertTrue(type.Body.self == Never.self)
    }
}
