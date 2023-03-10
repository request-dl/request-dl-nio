/*
 See LICENSE for this package's licensing information.
*/

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
