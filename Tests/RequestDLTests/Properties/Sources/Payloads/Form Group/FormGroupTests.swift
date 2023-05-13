/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable function_body_length
@RequestActor
class FormGroupTests: XCTestCase {

    func testSingleForm() async throws {
        // Given
        let key = "index"
        let value = 1

        let property = FormGroup {
            FormValue(key: key, value: value)
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers.getValue(forKey: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            await resolved.request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data("\(value)".utf8))
    }

    func testMultipleForm() async throws {
        // Given
        let key1 = "index"
        let value1 = 1

        let key2 = "template_image"
        let value2 = try ResourceFile("template_image").data()
        let fileName2 = "image.jpeg"
        let contentType2: ContentType = .jpeg

        let key3 = "template_document"
        let resourceFile3 = ResourceFile("template_document")
        let value3 = try resourceFile3.url()

        let property = FormGroup {
            FormValue(key: key1, value: value1)

            FormData(
                value2,
                forKey: key2,
                fileName: fileName2,
                type: contentType2
            )

            FormFile(
                value3,
                forKey: key3,
                fileName: nil,
                type: nil
            )
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers.getValue(forKey: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            await resolved.request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 3)

        // Then: - Property Index 0
        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key1)\""
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data("\(value1)".utf8))

        // Then: - Property Index 1
        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            "form-data; name=\"\(key2)\"; filename=\"\(fileName2)\""
        )

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Type"],
            contentType2.rawValue
        )

        XCTAssertEqual(
            multipartForm.items[1].contents,
            value2
        )

        // Then: - Property Index 2
        XCTAssertEqual(
            multipartForm.items[2].headers["Content-Disposition"],
            "form-data; name=\"\(key3)\"; filename=\"\(try resourceFile3.url().lastPathComponent)\""
        )

        XCTAssertEqual(
            multipartForm.items[2].headers["Content-Type"],
            ContentType.pdf.rawValue
        )

        XCTAssertEqual(
            multipartForm.items[2].contents,
            try resourceFile3.data()
        )
    }

    func testCollision() async throws {
        // Given
        let key = "index"
        let value1 = "123"
        let value2 = 124

        let property = FormGroup {
            FormValue(key: key, value: value1)
            FormValue(key: key, value: value2)
        }

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers.getValue(forKey: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            await resolved.request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(multipartForm.items.count, 2)

        XCTAssertEqual(multipartForm.items[0].contents, Data(value1.utf8))

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )

        XCTAssertEqual(multipartForm.items[1].contents, Data("\(value2)".utf8))

        XCTAssertEqual(
            multipartForm.items[1].headers["Content-Disposition"],
            "form-data; name=\"\(key)\""
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = FormGroup {}

        // Then
        try await assertNever(property.body)
    }

    func testGroup_whenPartLengthSet() async throws {
        // Given
        let length = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            FormGroup {
                FormValue(key: "key1", value: "foo")
                FormValue(key: "key2", value: "bar")
            }
            .payloadPartLength(length)
        })

        let sut = try await resolved.request.body?.buffers()

        // Then
        XCTAssertEqual(sut?.count, 1)
    }
}
// swiftlint:enable function_body_length
