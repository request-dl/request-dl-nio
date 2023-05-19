/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class MultipartBuilderTests: XCTestCase {

    func testSingleMultipartConstructor() async throws {
        // Given
        let value = "foo"
        let item = try FormItem(
            name: "string",
            factory: DataPayloadFactory(
                data: Data(value.utf8),
                contentType: nil
            )
        )

        // When
        let constructor = FormGroupBuilder([item])

        let multipartForm = try MultipartFormParser(
            constructor(),
            boundary: constructor.boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"string\""]
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testMultipleMultipartConstructor() async throws {
        // Given
        let value1 = "foo"
        let form1 = try FormItem(
            name: "string",
            factory: DataPayloadFactory(
                data: Data(value1.utf8),
                contentType: nil
            )
        )

        let value2 = CharacterSet.alphanumerics.description
        let form2 = try FormItem(
            name: "document",
            filename: "document.pdf",
            factory: DataPayloadFactory(
                data: Data(value2.utf8),
                contentType: .pdf
            )
        )

        // When
        let constructor = FormGroupBuilder([form1, form2])

        let multipartForm = try MultipartFormParser(
            constructor(),
            boundary: constructor.boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 2)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"string\""]
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value1.utf8))

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            ["form-data; name=\"document\"; filename=\"document.pdf\""]
        )

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Type"],
            ["application/pdf"]
        )

        XCTAssertEqual(multipartForm.items[1].contents, Data(value2.utf8))
    }
}
