/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class MultipartFormConstructorTests: XCTestCase {

    func testSingleMultipartConstructor() async throws {
        // Given
        let value = "foo"
        let item = MultipartItem(
            name: "string",
            data: Internals.DataBuffer(value.utf8)
        )

        // When
        let constructor = MultipartBuilder([item])

        let multipartForm = try MultipartFormParser(
            constructor(),
            boundary: constructor.boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"string\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testMultipleMultipartConstructor() async throws {
        // Given
        let value1 = "foo"
        let form1 = MultipartItem(
            name: "string",
            data: Internals.DataBuffer(value1.utf8)
        )

        let value2 = CharacterSet.alphanumerics.description
        let form2 = MultipartItem(
            name: "document",
            filename: "document.pdf",
            contentType: .pdf,
            data: Internals.DataBuffer(value2.utf8)
        )

        // When
        let constructor = MultipartBuilder([form1, form2])

        let multipartForm = try MultipartFormParser(
            constructor(),
            boundary: constructor.boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 2)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"string\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value1.utf8))

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            "form-data; name=\"document\"; filename=\"document.pdf\""
        )

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Type"],
            "application/pdf"
        )

        XCTAssertEqual(multipartForm.items[1].contents, Data(value2.utf8))
    }
}
