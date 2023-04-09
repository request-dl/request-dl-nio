/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ContentTypeTests: XCTestCase {

    func testJsonTypeRawValue() async throws {
        XCTAssertEqual(ContentType.json, "application/json")
    }

    func testXmlTypeRawValue() async throws {
        XCTAssertEqual(ContentType.xml, "application/xml")
    }

    func testFormDataTypeRawValue() async throws {
        XCTAssertEqual(ContentType.formData, "form-data")
    }

    func testFormURLEncodedTypeRawValue() async throws {
        XCTAssertEqual(ContentType.formURLEncoded, "application/x-www-form-urlencoded")
    }

    func testTextTypeRawValue() async throws {
        XCTAssertEqual(ContentType.text, "text/plain")
    }

    func testHtmlTypeRawValue() async throws {
        XCTAssertEqual(ContentType.html, "text/html")
    }

    func testCssTypeRawValue() async throws {
        XCTAssertEqual(ContentType.css, "text/css")
    }

    func testJavascriptTypeRawValue() async throws {
        XCTAssertEqual(ContentType.javascript, "text/javascript")
    }

    func testGifTypeRawValue() async throws {
        XCTAssertEqual(ContentType.gif, "image/gif")
    }

    func testPngTypeRawValue() async throws {
        XCTAssertEqual(ContentType.png, "image/png")
    }

    func testJpegTypeRawValue() async throws {
        XCTAssertEqual(ContentType.jpeg, "image/jpeg")
    }

    func testBmpTypeRawValue() async throws {
        XCTAssertEqual(ContentType.bmp, "image/bmp")
    }

    func testWebpTypeRawValue() async throws {
        XCTAssertEqual(ContentType.webp, "image/webp")
    }

    func testMidiTypeRawValue() async throws {
        XCTAssertEqual(ContentType.midi, "audio/midi")
    }

    func testMpegTypeRawValue() async throws {
        XCTAssertEqual(ContentType.mpeg, "audio/mpeg")
    }

    func testWavTypeRawValue() async throws {
        XCTAssertEqual(ContentType.wav, "audio/wav")
    }

    func testPdfTypeRawValue() async throws {
        XCTAssertEqual(ContentType.pdf, "application/pdf")
    }
}
