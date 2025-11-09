/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ContentTypeTests {

    @Test
    func jsonTypeRawValue() async throws {
        #expect(ContentType.json == "application/json")
    }

    @Test
    func xmlTypeRawValue() async throws {
        #expect(ContentType.xml == "application/xml")
    }

    @Test
    func formDataTypeRawValue() async throws {
        #expect(ContentType.formData == "form-data")
    }

    @Test
    func formURLEncodedTypeRawValue() async throws {
        #expect(ContentType.formURLEncoded == "application/x-www-form-urlencoded")
    }

    @Test
    func textTypeRawValue() async throws {
        #expect(ContentType.text == "text/plain")
    }

    @Test
    func htmlTypeRawValue() async throws {
        #expect(ContentType.html == "text/html")
    }

    @Test
    func cssTypeRawValue() async throws {
        #expect(ContentType.css == "text/css")
    }

    @Test
    func javascriptTypeRawValue() async throws {
        #expect(ContentType.javascript == "text/javascript")
    }

    @Test
    func gifTypeRawValue() async throws {
        #expect(ContentType.gif == "image/gif")
    }

    @Test
    func pngTypeRawValue() async throws {
        #expect(ContentType.png == "image/png")
    }

    @Test
    func jpegTypeRawValue() async throws {
        #expect(ContentType.jpeg == "image/jpeg")
    }

    @Test
    func bmpTypeRawValue() async throws {
        #expect(ContentType.bmp == "image/bmp")
    }

    @Test
    func webpTypeRawValue() async throws {
        #expect(ContentType.webp == "image/webp")
    }

    @Test
    func midiTypeRawValue() async throws {
        #expect(ContentType.midi == "audio/midi")
    }

    @Test
    func mpegTypeRawValue() async throws {
        #expect(ContentType.mpeg == "audio/mpeg")
    }

    @Test
    func wavTypeRawValue() async throws {
        #expect(ContentType.wav == "audio/wav")
    }

    @Test
    func pdfTypeRawValue() async throws {
        #expect(ContentType.pdf == "application/pdf")
    }

    @Test
    func contentType_withStringLossless() async throws {
        // Given
        let contentType = ContentType.pdf

        // When
        let string = String(contentType)
        let losslessContentType = ContentType(string)

        // Then
        #expect(string == contentType.description)
        #expect(losslessContentType == contentType)
    }
}
