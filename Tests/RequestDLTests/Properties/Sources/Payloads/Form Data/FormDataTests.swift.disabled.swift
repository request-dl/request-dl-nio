/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@available(*, deprecated)
class FormDataTests: XCTestCase {

    struct Mock: Codable {
        let foo: String
        let date: Date
    }

    func testDataFormWithFileName() async throws {
        // Given
        let value = "foo"

        let property = FormData(
            Data(value.utf8),
            forKey: "raw_string",
            fileName: "data.txt",
            type: .text
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try await MultipartFormParser(
            resolved.request.body?.buffers() ?? [],
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, ["multipart/form-data; boundary=\"\(boundary)\""])
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(property.name)\"; filename=\"\(property.filename)\""]
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            [String(ContentType.text)]
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testDataFormWithoutFileName() async throws {
        // Given
        let value = "foo"

        let property = FormData(
            Data(value.utf8),
            forKey: "raw_string",
            type: .text
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try await MultipartFormParser(
            resolved.request.body?.buffers() ?? [],
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, ["multipart/form-data; boundary=\"\(boundary)\""])
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            ["form-data; name=\"\(property.name)\"; filename=\"\""]
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            ["text/plain; charset=UTF-8"]
        )

        XCTAssertEqual(multipartForm.items[0].contents, Data(value.utf8))
    }

    func testEncodableData() async throws {
        // Given
        let mock = Mock(
            foo: "bar",
            date: Date()
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970

        // When
        let property = FormData(
            mock,
            forKey: "data",
            encoder: encoder
        )

        let propertyData = try property.factory().getData() ?? Data()

        let expectedData = try encoder.encode(mock)
        let expectedMock = try decoder.decode(Mock.self, from: propertyData)

        // Then
        XCTAssertEqual(property.factory.contentType, .json)
        XCTAssertEqual(property.filename, "")
        XCTAssertEqual(property.name, "data")
        XCTAssertEqual(propertyData, expectedData)
        XCTAssertEqual(expectedMock.foo, mock.foo)
        XCTAssertEqual(expectedMock.date.seconds, mock.date.seconds)
    }

    func testEncodableWithFilename() async throws {
        // Given
        let fileName = "contents.json"

        // When
        let property = FormData(
            Mock(foo: "bar", date: Date()),
            forKey: "data",
            fileName: fileName
        )

        // Then
        XCTAssertEqual(property.filename, fileName)
    }

    func testNeverBody() async throws {
        // Given
        let property = FormData(Data(), forKey: "key", fileName: "123", type: .json)

        // Then
        try await assertNever(property.body)
    }

    func testData_whenPartLengthSet() async throws {
        // Given
        let length = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            FormData(
                Mock(foo: "bar", date: Date()),
                forKey: "data",
                fileName: "contents.json"
            )
            .payloadPartLength(length)
        })

        let sut = try await resolved.request.body?.buffers()

        // Then
        XCTAssertEqual(sut?.count, 1)
    }
}
