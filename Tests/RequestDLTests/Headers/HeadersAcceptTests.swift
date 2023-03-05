//
//  HeadersAcceptTests.swift
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
}
