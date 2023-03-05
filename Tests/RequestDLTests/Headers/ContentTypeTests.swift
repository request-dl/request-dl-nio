//
//  ContentTypeTests.swift
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

final class ContentTypeTests: XCTestCase {

    func testJsonTypeRawValue() {
        XCTAssertEqual(ContentType.json, "application/json")
    }

    func testXmlTypeRawValue() {
        XCTAssertEqual(ContentType.xml, "application/xml")
    }

    func testFormDataTypeRawValue() {
        XCTAssertEqual(ContentType.formData, "form-data")
    }

    func testFormURLEncodedTypeRawValue() {
        XCTAssertEqual(ContentType.formURLEncoded, "application/x-www-form-urlencoded")
    }

    func testTextTypeRawValue() {
        XCTAssertEqual(ContentType.text, "text/plain")
    }

    func testHtmlTypeRawValue() {
        XCTAssertEqual(ContentType.html, "text/html")
    }

    func testCssTypeRawValue() {
        XCTAssertEqual(ContentType.css, "text/css")
    }

    func testJavascriptTypeRawValue() {
        XCTAssertEqual(ContentType.javascript, "text/javascript")
    }

    func testGifTypeRawValue() {
        XCTAssertEqual(ContentType.gif, "image/gif")
    }

    func testPngTypeRawValue() {
        XCTAssertEqual(ContentType.png, "image/png")
    }

    func testJpegTypeRawValue() {
        XCTAssertEqual(ContentType.jpeg, "image/jpeg")
    }

    func testBmpTypeRawValue() {
        XCTAssertEqual(ContentType.bmp, "image/bmp")
    }

    func testWebpTypeRawValue() {
        XCTAssertEqual(ContentType.webp, "image/webp")
    }

    func testMidiTypeRawValue() {
        XCTAssertEqual(ContentType.midi, "audio/midi")
    }

    func testMpegTypeRawValue() {
        XCTAssertEqual(ContentType.mpeg, "audio/mpeg")
    }

    func testWavTypeRawValue() {
        XCTAssertEqual(ContentType.wav, "audio/wav")
    }

    func testPdfTypeRawValue() {
        XCTAssertEqual(ContentType.pdf, "application/pdf")
    }
}
