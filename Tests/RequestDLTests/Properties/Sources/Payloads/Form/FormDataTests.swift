/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import RequestDLInternals
@testable import RequestDL

final class FormDataTests: XCTestCase {

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
        let (_, request) = try await resolve(TestProperty(property))

        let contentTypeHeader = request.headers.getValue(forKey: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            await request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(property.key)\"; filename=\"\(property.fileName)\""
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            property.contentType.rawValue
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
        let (_, request) = try await resolve(TestProperty(property))

        let contentTypeHeader = request.headers.getValue(forKey: "Content-Type")
        let boundary = MultipartFormParser.extractBoundary(contentTypeHeader) ?? "nil"

        let multipartForm = try MultipartFormParser(
            await request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(multipartForm.items.count, 1)

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Disposition"],
            "form-data; name=\"\(property.key)\"; filename=\"\""
        )

        XCTAssertEqual(
            multipartForm.items[0].headers["Content-Type"],
            property.contentType.rawValue
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

        let expectedData = try encoder.encode(mock)
        let expectedMock = try decoder.decode(Mock.self, from: property.data)

        // Then
        XCTAssertEqual(property.contentType, .json)
        XCTAssertEqual(property.fileName, "")
        XCTAssertEqual(property.key, "data")
        XCTAssertEqual(property.data, expectedData)
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
        XCTAssertEqual(property.fileName, fileName)
    }

    func testNeverBody() async throws {
        // Given
        let property = FormData(Data(), forKey: "key", fileName: "123", type: .json)

        // Then
        try await assertNever(property.body)
    }
}