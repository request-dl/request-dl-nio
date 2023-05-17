/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class FormFileTests: XCTestCase {

    func testFileFormWithFileNameAndContentType() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        let property = FormFile(
            url,
            forKey: "document",
            fileName: "file.pdf",
            type: .pdf
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try MultipartFormParser(
            await resolved.request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, ["multipart/form-data; boundary=\"\(boundary)\""])
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

    func testEmptyFileName() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        let property = FormFile(
            url,
            forKey: "document",
            fileName: "",
            type: .pdf
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        let contentTypeHeader = resolved.request.headers["Content-Type"] ?? []
        let boundary = contentTypeHeader.first.flatMap {
            MultipartFormParser.extractBoundary($0)
        } ?? "nil"

        let multipartForm = try MultipartFormParser(
            await resolved.request.body?.data() ?? Data(),
            boundary: boundary
        ).parse()

        // Then
        XCTAssertEqual(contentTypeHeader, ["multipart/form-data; boundary=\"\(boundary)\""])
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

    func testFileNameResolver() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        // When
        let fileName = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: .pdf
        ).fileName

        // Then
        XCTAssertEqual(fileName, "bar.pdf")
    }

    func testContentTypeResolver() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")
            .appendingPathExtension("pdf")

        try Data(value.utf8).write(to: url)

        // When
        let contentType = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: nil
        ).contentType

        // Then
        XCTAssertEqual(contentType, .pdf)
    }

    func testOctetStreamResolved() async throws {
        // Given
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")

        try Data(value.utf8).write(to: url)

        // When
        let contentType = FormFile(
            url,
            forKey: "document",
            fileName: nil,
            type: nil
        ).contentType

        // Then
        XCTAssertEqual(contentType, "application/octet-stream")
    }

    func testNeverBody() async throws {
        // Given
        let property = FormFile(
            FileManager.default.temporaryDirectory,
            forKey: "key",
            fileName: nil,
            type: nil
        )

        // Then
        try await assertNever(property.body)
    }

    func testFile_whenPartLengthSet() async throws {
        // Given
        let length = 1_024
        let value = "foo"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bar")

        try Data(value.utf8).write(to: url)

        // When
        let resolved = try await resolve(TestProperty {
            FormFile(
                url,
                forKey: "document",
                fileName: nil,
                type: nil
            )
            .payloadPartLength(length)
        })

        let sut = try await resolved.request.body?.buffers()

        // Then
        XCTAssertEqual(sut?.count, 1)
    }
}
